--- @module server.accounts.accounts
--- CRUD and balance-mutation logic for `tb_accounts`, the resource's
--- single authoritative balance table (personal, savings and business rows
--- alike). Every money movement in the resource funnels through Credit /
--- Debit / Transfer here so it gets an audit row in tb_transactions and a
--- bridge push (server/bridge/external_bridge.lua) for free.
---
--- Balance guards are single conditional UPDATEs
--- (`... WHERE balance >= amount`), which is the atomic protection against
--- two concurrent debits both passing a balance check, deliberately not a
--- full SQL transaction (see Transfer's compensating step for the one
--- multi-statement case).

TbAccounts = {}

--- Converts a raw oxmysql row (snake_case, 0/1 tinyints) into the camelCase
--- TbAccount shape the rest of the resource works with.
---@param row table
---@return TbAccount
function TbAccounts.RowToAccount(row)
	return {
		id = row.id,
		type = row.type,
		ownerIdentifier = row.owner_identifier,
		jobName = row.job_name,
		number = row.number,
		name = row.name,
		balance = row.balance,
		isDefault = TbUtils.ToBool(row.is_default),
		isTreasury = TbUtils.ToBool(row.is_treasury),
		interestRate = row.interest_rate and tonumber(row.interest_rate) or nil,
		lockedUntil = row.locked_until,
		historyClearedAt = row.history_cleared_at,
		createdAt = row.created_at,
	}
end

--- Whether money may leave the account right now. Only savings accounts
--- ever lock (Config.Savings.WithdrawLockSeconds); checked in SQL so the
--- comparison uses the database clock the lock was written with.
---@param accountId integer
---@return boolean locked
local function IsLocked(accountId)
	local ok, row = TbDb.SelectOne(
		"SELECT 1 AS locked FROM tb_accounts WHERE id = ? AND type = 'savings' AND locked_until IS NOT NULL AND locked_until > NOW()",
		{ accountId }
	)

	return ok and row ~= nil
end

--- Re-arms the withdrawal lock after real money arrives in a savings
--- account. Interest credits are excluded on purpose, otherwise every
--- daily tick would push the unlock date out forever.
---@param accountId integer
---@param transactionType TbTransactionType
local function ApplyDepositLock(accountId, transactionType)
	local seconds = Config.Savings.WithdrawLockSeconds or 0

	if seconds <= 0 or transactionType == TbEnums.TransactionType.INTEREST then
		return
	end

	TbDb.Update(
		"UPDATE tb_accounts SET locked_until = DATE_ADD(NOW(), INTERVAL ? SECOND) WHERE id = ? AND type = 'savings'",
		{ seconds, accountId }
	)
end

--- Looks up a live (non-deleted) account by id.
---@param accountId integer
---@return TbAccount?
function TbAccounts.GetById(accountId)
	local ok, row = TbDb.SelectOne('SELECT * FROM tb_accounts WHERE id = ? AND deleted_at IS NULL', { accountId })

	if not ok or not row then
		return nil
	end

	return TbAccounts.RowToAccount(row)
end

--- Looks up a live account by its player-facing number ('920-48271039').
---@param number string
---@return TbAccount?
function TbAccounts.GetByNumber(number)
	if type(number) ~= 'string' then
		return nil
	end

	local ok, row = TbDb.SelectOne('SELECT * FROM tb_accounts WHERE number = ? AND deleted_at IS NULL', { (number:gsub('%s', '')) })

	if not ok or not row then
		return nil
	end

	return TbAccounts.RowToAccount(row)
end

--- A player's default personal account, if they have one yet.
---@param identifier string
---@return TbAccount?
function TbAccounts.GetDefaultForPlayer(identifier)
	local ok, row = TbDb.SelectOne(
		"SELECT * FROM tb_accounts WHERE owner_identifier = ? AND type = 'personal' AND is_default = 1 AND deleted_at IS NULL",
		{ identifier }
	)

	if not ok or not row then
		return nil
	end

	return TbAccounts.RowToAccount(row)
end

--- Every live personal + savings account a player owns, default first.
---@param identifier string
---@return TbAccount[]
function TbAccounts.ListForPlayer(identifier)
	local ok, rows = TbDb.SelectMany(
		[[SELECT * FROM tb_accounts
			WHERE owner_identifier = ? AND type IN ('personal', 'savings') AND deleted_at IS NULL
			ORDER BY is_default DESC, type ASC, created_at ASC]],
		{ identifier }
	)

	if not ok then
		return {}
	end

	local accounts = {}

	for i, row in ipairs(rows) do
		accounts[i] = TbAccounts.RowToAccount(row)
	end

	return accounts
end

--- Returns the account only if `identifier` owns it (personal or savings).
--- The ownership check every personal-account action goes through.
---@param identifier string
---@param accountId integer
---@return TbAccount?
function TbAccounts.GetOwned(identifier, accountId)
	local account = TbAccounts.GetById(accountId)

	if not account or account.ownerIdentifier ~= identifier then
		return nil
	end

	if account.type ~= TbEnums.AccountType.PERSONAL and account.type ~= TbEnums.AccountType.SAVINGS then
		return nil
	end

	return account
end

--- Generates an account number guaranteed not to collide with an existing
--- one. Collisions are astronomically unlikely at 8 digits but checked
--- anyway, this runs once per account creation, correctness is free.
---@return string?
local function GenerateUniqueNumber()
	for _ = 1, 10 do
		local candidate = TbUtils.GenerateAccountNumber()
		local ok, existing = TbDb.SelectOne('SELECT id FROM tb_accounts WHERE number = ?', { candidate })

		if ok and not existing then
			return candidate
		end
	end

	TbLogger.Error('accounts', 'could not generate a unique account number after 10 attempts')
	return nil
end

--- Inserts a new account row. Internal building block for personal.lua and
--- the job-account bootstrap below, callers decide type/owner/defaults.
---@param fields { type: TbAccountType, ownerIdentifier: string?, jobName: string?, name: string, balance: integer?, isDefault: boolean?, interestRate: number? }
---@return TbAccount?
function TbAccounts.Create(fields)
	local number = GenerateUniqueNumber()

	if not number then
		return nil
	end

	local ok, insertId = TbDb.Insert(
		[[INSERT INTO tb_accounts (type, owner_identifier, job_name, number, name, balance, is_default, interest_rate)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?)]],
		{
			fields.type, fields.ownerIdentifier, fields.jobName, number, fields.name,
			fields.balance or 0, fields.isDefault and 1 or 0, fields.interestRate,
		}
	)

	if not ok or not insertId then
		return nil
	end

	local account = TbAccounts.GetById(insertId)

	if account and (fields.balance or 0) > 0 then
		-- The opening balance is real money the server created, record it
		-- so the statement doesn't start from an unexplained non-zero total.
		TbDb.Insert(
			'INSERT INTO tb_transactions (to_account_id, type, amount, balance_after, note) VALUES (?, ?, ?, ?, ?)',
			{ account.id, TbEnums.TransactionType.DEPOSIT, account.balance, account.balance, 'Opening balance' }
		)
	end

	return account
end

--- The player's default personal account, creating their very first
--- account (with Config.Accounts.StartBalance.First) if they have none.
--- This is the one auto-provisioning entry point, every other account is
--- created explicitly by the player (server/accounts/personal.lua).
---@param identifier string
---@return TbAccount?
function TbAccounts.GetOrCreateDefault(identifier)
	local existing = TbAccounts.GetDefaultForPlayer(identifier)

	if existing then
		return existing
	end

	-- A player could have non-default accounts but no default only if the
	-- default was corrupted externally, promote the oldest personal one
	-- rather than silently creating a second "first" account.
	for _, account in ipairs(TbAccounts.ListForPlayer(identifier)) do
		if account.type == TbEnums.AccountType.PERSONAL then
			TbDb.Update('UPDATE tb_accounts SET is_default = 1 WHERE id = ?', { account.id })
			return TbAccounts.GetById(account.id)
		end
	end

	-- StartBalance.First = false: the framework already hands out starting
	-- money, so the account takes over whatever its bank balance holds.
	local startBalance = Config.Accounts.StartBalance.First
	local frameworkSource = TbFramework.GetSourceByIdentifier(identifier)

	if startBalance == false or startBalance == nil then
		startBalance = frameworkSource and tonumber(TbFramework.GetBank(frameworkSource)) or 0
	end

	return TbAccounts.Create({
		type = TbEnums.AccountType.PERSONAL,
		ownerIdentifier = identifier,
		name = 'Main account',
		balance = math.max(0, math.floor(startBalance)),
		isDefault = true,
	})
end

--- The business account linked to an ESX job, created on first touch so a
--- fresh job needs zero setup before its boss can open the terminal.
---@param jobName string
---@param label string?
---@return TbAccount?
function TbAccounts.GetOrCreateJobAccount(jobName, label)
	local ok, row = TbDb.SelectOne(
		"SELECT * FROM tb_accounts WHERE type = 'society' AND job_name = ? AND deleted_at IS NULL",
		{ jobName }
	)

	if ok and row then
		return TbAccounts.RowToAccount(row)
	end

	return TbAccounts.Create({
		type = TbEnums.AccountType.SOCIETY,
		jobName = jobName,
		name = label or jobName,
		balance = 0,
	})
end

--- Records a transaction row and pushes the account's new balance to its
--- external mirror (if any). Shared tail of Credit/Debit/Transfer.
---@param fromAccountId integer?
---@param toAccountId integer?
---@param transactionType TbTransactionType
---@param amount integer
---@param balanceAfter integer
---@param actorIdentifier string?
---@param note string?
---@param metadata table?
---@return integer? transactionId
local function RecordTransaction(fromAccountId, toAccountId, transactionType, amount, balanceAfter, actorIdentifier, note, metadata)
	local encodedMetadata = nil

	if metadata then
		local ok, encoded = pcall(json.encode, metadata)
		encodedMetadata = ok and encoded or nil
	end

	local ok, insertId = TbDb.Insert(
		[[INSERT INTO tb_transactions
			(from_account_id, to_account_id, type, amount, balance_after, actor_identifier, note, metadata)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?)]],
		{ fromAccountId, toAccountId, transactionType, amount, balanceAfter, actorIdentifier, note, encodedMetadata }
	)

	-- Every money movement in the resource passes here, this one line is
	-- the complete ledger in the console / ox logger.
	TbLogger.Debug('ledger', transactionType, {
		id = insertId, from = fromAccountId, to = toAccountId, amount = amount,
		balance_after = balanceAfter, actor = actorIdentifier, note = note,
	})

	if not ok then
		TbLogger.Error('ledger', 'balance changed but the transaction row could not be written', {
			from = fromAccountId, to = toAccountId, type = transactionType, amount = amount,
		})
	end

	return ok and insertId or nil
end

--- Mirrors a mutated account outward. Guarded so accounts.lua stays usable
--- even if the bridge module failed to load.
---@param accountId integer
local function PushMirror(accountId)
	if not TbExternalBridge then
		return
	end

	local account = TbAccounts.GetById(accountId)

	if account then
		TbExternalBridge.PushBalance(account)
	end
end

--- Credits (adds money to) an account.
---@param accountId integer
---@param amount integer
---@param transactionType TbTransactionType
---@param actorIdentifier string?
---@param note string?
---@param metadata table?
---@return boolean ok
---@return integer? newBalance
function TbAccounts.Credit(accountId, amount, transactionType, actorIdentifier, note, metadata)
	amount = TbUtils.RoundMoney(amount)

	if amount <= 0 then
		return false, nil
	end

	local ok, affected = TbDb.Update(
		'UPDATE tb_accounts SET balance = balance + ? WHERE id = ? AND deleted_at IS NULL',
		{ amount, accountId }
	)

	if not ok or affected == 0 then
		return false, nil
	end

	local account = TbAccounts.GetById(accountId)

	if not account then
		return false, nil
	end

	RecordTransaction(nil, accountId, transactionType, amount, account.balance, actorIdentifier, note, metadata)
	ApplyDepositLock(accountId, transactionType)
	PushMirror(accountId)

	return true, account.balance
end

--- Debits (removes money from) an account. The balance check and the
--- decrement happen in one `UPDATE ... WHERE balance >= amount`, the
--- atomic guard against a negative-balance race.
---@param accountId integer
---@param amount integer
---@param transactionType TbTransactionType
---@param actorIdentifier string?
---@param note string?
---@param metadata table?
---@return boolean ok
---@return string? errorReason 'invalid_amount' | 'insufficient_funds' | 'not_found' | 'savings_locked'
---@return integer? newBalance
function TbAccounts.Debit(accountId, amount, transactionType, actorIdentifier, note, metadata)
	amount = TbUtils.RoundMoney(amount)

	if amount <= 0 then
		return false, 'invalid_amount'
	end

	if IsLocked(accountId) then
		return false, 'savings_locked'
	end

	local ok, affected = TbDb.Update(
		'UPDATE tb_accounts SET balance = balance - ? WHERE id = ? AND balance >= ? AND deleted_at IS NULL',
		{ amount, accountId, amount }
	)

	if not ok then
		return false, 'not_found'
	end

	if affected == 0 then
		return false, TbAccounts.GetById(accountId) and 'insufficient_funds' or 'not_found'
	end

	local account = TbAccounts.GetById(accountId)

	if not account then
		return false, 'not_found'
	end

	RecordTransaction(accountId, nil, transactionType, amount, account.balance, actorIdentifier, note, metadata)
	PushMirror(accountId)

	return true, nil, account.balance
end

--- Moves money between two accounts as a single audit row. Debit first
--- (atomic guard), then credit; if the credit leg fails after the debit
--- committed, the debit is reversed and a critical alert logged, the
--- compensating step that stands in for a multi-statement SQL transaction.
---@param fromAccountId integer
---@param toAccountId integer
---@param amount integer
---@param transactionType TbTransactionType Usually 'transfer'; standing orders / invoice payments pass their own.
---@param actorIdentifier string?
---@param note string?
---@param metadata table?
---@param allowNegative boolean? Take the money even if the balance ends below zero.
---@return boolean ok
---@return string? errorReason 'invalid_amount' | 'same_account' | 'insufficient_funds' | 'not_found' | 'credit_failed' | 'savings_locked'
function TbAccounts.Transfer(fromAccountId, toAccountId, amount, transactionType, actorIdentifier, note, metadata, allowNegative)
	amount = TbUtils.RoundMoney(amount)

	if amount <= 0 then
		return false, 'invalid_amount'
	end

	if fromAccountId == toAccountId then
		return false, 'same_account'
	end

	if not TbAccounts.GetById(toAccountId) then
		return false, 'not_found'
	end

	-- allowNegative is for debts (overdue bills): taken even if the account goes below zero or is locked
	if not allowNegative and IsLocked(fromAccountId) then
		return false, 'savings_locked'
	end

	local debitOk, debited = TbDb.Update(
		allowNegative and 'UPDATE tb_accounts SET balance = balance - ? WHERE id = ? AND deleted_at IS NULL'
			or 'UPDATE tb_accounts SET balance = balance - ? WHERE id = ? AND balance >= ? AND deleted_at IS NULL',
		allowNegative and { amount, fromAccountId } or { amount, fromAccountId, amount }
	)

	if not debitOk then
		return false, 'not_found'
	end

	if debited == 0 then
		return false, TbAccounts.GetById(fromAccountId) and 'insufficient_funds' or 'not_found'
	end

	local creditOk, credited = TbDb.Update(
		'UPDATE tb_accounts SET balance = balance + ? WHERE id = ? AND deleted_at IS NULL',
		{ amount, toAccountId }
	)

	if not creditOk or credited == 0 then
		TbDb.Update('UPDATE tb_accounts SET balance = balance + ? WHERE id = ?', { amount, fromAccountId })

		if TbLog then
			TbLog('security_alerts', 'Transfer credit leg failed, debit reversed', {
				{ name = 'From', value = tostring(fromAccountId) },
				{ name = 'To', value = tostring(toAccountId) },
				{ name = 'Amount', value = tostring(amount) },
			}, Config.Logs.Colors.danger)
		end

		return false, 'credit_failed'
	end

	local toAccount = TbAccounts.GetById(toAccountId)

	RecordTransaction(fromAccountId, toAccountId, transactionType or TbEnums.TransactionType.TRANSFER, amount,
		toAccount and toAccount.balance or 0, actorIdentifier, note, metadata)
	ApplyDepositLock(toAccountId, transactionType or TbEnums.TransactionType.TRANSFER)
	PushMirror(fromAccountId)
	PushMirror(toAccountId)

	return true, nil
end

--- Renames an account. No ownership check here, personal.lua / members
--- callers do that against their own rules first.
---@param accountId integer
---@param name string
---@return boolean ok
function TbAccounts.Rename(accountId, name)
	local ok, affected = TbDb.Update('UPDATE tb_accounts SET name = ? WHERE id = ? AND deleted_at IS NULL', { name, accountId })
	return ok and affected > 0
end

--- Soft-deletes an account. Balance must already have been moved out by the
--- caller (personal.lua sweeps it into the default account first).
---@param accountId integer
---@return boolean ok
function TbAccounts.SoftDelete(accountId)
	local ok, affected = TbDb.Update(
		'UPDATE tb_accounts SET deleted_at = NOW(), is_default = 0 WHERE id = ? AND deleted_at IS NULL',
		{ accountId }
	)

	return ok and affected > 0
end

--- Makes `accountId` the player's default, clearing the flag on the rest.
--- Two statements, but the worst case of a crash in between is "no default
--- for a moment", which GetOrCreateDefault self-heals on next access.
---@param identifier string
---@param accountId integer
---@return boolean ok
function TbAccounts.SetDefault(identifier, accountId)
	TbDb.Update("UPDATE tb_accounts SET is_default = 0 WHERE owner_identifier = ? AND type = 'personal'", { identifier })

	local ok, affected = TbDb.Update(
		"UPDATE tb_accounts SET is_default = 1 WHERE id = ? AND owner_identifier = ? AND type = 'personal' AND deleted_at IS NULL",
		{ accountId, identifier }
	)

	if not ok or affected == 0 then
		-- Restore a sane state rather than leaving the player with no default.
		TbAccounts.GetOrCreateDefault(identifier)
		return false
	end

	PushMirror(accountId)
	return true
end

--- Resolves a transfer/invoice recipient typed by a player: an account
--- number first, otherwise an ESX identifier (their default account).
---@param input string
---@return TbAccount?
function TbAccounts.ResolveRecipient(input)
	if type(input) == 'number' then
		input = tostring(math.floor(input))
	end

	if type(input) ~= 'string' then
		return nil
	end

	input = input:gsub('^%s+', ''):gsub('%s+$', '')

	if input == '' then
		return nil
	end

	-- An account number carries the clearing prefix ('920-48271039'), so it
	-- can never collide with a bare server id.
	local byNumber = TbAccounts.GetByNumber(input)

	if byNumber then
		return byNumber
	end

	-- A plain number is the ONLINE SERVER ID of the recipient, that is what
	-- a player can actually read off the screen. Identifiers stay supported
	-- below for the server exports and admin tooling, but nobody is expected
	-- to type one.
	local serverId = input:match('^%d+$') and tonumber(input) or nil

	if serverId then
		local identifier = TbFramework.GetIdentifier(serverId)

		if identifier then
			return TbAccounts.GetOrCreateDefault(identifier)
		end

		-- A number that matches nobody online is a mistyped id, not an
		-- identifier, stop here rather than fall through to a lookup that
		-- cannot possibly match.
		return nil
	end

	return TbAccounts.GetDefaultForPlayer(input)
end
