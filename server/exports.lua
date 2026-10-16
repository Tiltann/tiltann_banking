--- @module server.exports
--- Public server exports for third-party resources (shops, jobs, garages).
--- Described with examples in exports.md.
--- Every export is pcall-wrapped so a bad argument from another script
--- never crashes this one, failures return `false`/`nil`, never throw.
---
--- Usage from another resource:
---   exports.tiltann_banking:AddMoney(identifier, 500, 'Paycheck')
---   local ok = exports.tiltann_banking:RemoveMoney(identifier, 250, 'Shop purchase')
---   local balance = exports.tiltann_banking:GetBalance(identifier)
---   exports.tiltann_banking:AddSocietyMoney('mechanic', 1200, 'Repair job')

--- Wraps an export body so any error becomes a logged false/nil result.
---@param name string
---@param fn function
local function SafeExport(name, fn)
	exports(name, function(...)
		local args = table.pack(...)
		local ok, a, b = TbSafe.Run(('export:%s'):format(name), fn, ...)

		if not ok then
			TbLogger.Error('export', ('%s failed, check the caller\'s arguments'):format(name), { args = args })
			return false, nil
		end

		TbLogger.Debug('export', name, { args = args, result = a })
		return a, b
	end)
end

--- Finds one of a player's own accounts. `account` is optional:
---   nil              the default (main) account
---   1, 2, 3 ...      the position in GetAccounts (1 = main, then the others)
---   '920-48271039'   an account number, which must belong to the player
---@param identifier string
---@param account integer|string|nil
---@return TbAccount?
local function ResolveOwnedAccount(identifier, account)
	if account == nil then
		return TbAccounts.GetOrCreateDefault(identifier)
	end

	local position = tonumber(account)

	if position and tostring(account):match('^%d+$') then
		TbAccounts.GetOrCreateDefault(identifier)
		return TbAccounts.ListForPlayer(identifier)[position]
	end

	local byNumber = type(account) == 'string' and TbAccounts.GetByNumber(account) or nil
	return byNumber and TbAccounts.GetOwned(identifier, byNumber.id) or nil
end

---@param identifier string
---@return TbAccount[]
local function ListWithIndex(identifier)
	TbAccounts.GetOrCreateDefault(identifier)

	local accounts = TbAccounts.ListForPlayer(identifier)

	for i, account in ipairs(accounts) do
		account.index = i
	end

	return accounts
end

---@param source integer
---@return string?
local function IdentifierOf(source)
	return TbFramework.GetIdentifier(tonumber(source) or 0)
end

---@param identifier string?
---@param amount any
---@param note string?
---@param account integer|string|nil
---@return boolean ok
---@return string? errorReason
local function Credit(identifier, amount, note, account)
	local target = identifier and ResolveOwnedAccount(identifier, account)

	if not target then
		return false, 'not_found'
	end

	local ok = TbAccounts.Credit(target.id, tonumber(amount) or 0, TbEnums.TransactionType.DEPOSIT, nil, note or 'External credit')
	return ok, ok and nil or 'invalid_amount'
end

---@param identifier string?
---@param amount any
---@param note string?
---@param account integer|string|nil
---@return boolean ok
---@return string? errorReason
local function Debit(identifier, amount, note, account)
	local target = identifier and ResolveOwnedAccount(identifier, account)

	if not target then
		return false, 'not_found'
	end

	return TbAccounts.Debit(target.id, tonumber(amount) or 0, TbEnums.TransactionType.WITHDRAW, nil, note or 'External debit')
end

--- The player's default account (their "bank balance" from a script's point of view).
---@param identifier string
---@return TbAccount?
SafeExport('GetDefaultAccount', function(identifier)
	return TbAccounts.GetOrCreateDefault(identifier)
end)

--- Every personal and savings account the player owns, main account first.
--- Each entry has an `index` (1 = main) that the other exports accept as `account`.
---@param identifier string
---@return TbAccount[]
SafeExport('GetAccounts', function(identifier)
	return ListWithIndex(identifier)
end)

---@param source integer
---@return TbAccount[]
SafeExport('GetAccountsBySource', function(source)
	local identifier = IdentifierOf(source)
	return identifier and ListWithIndex(identifier) or {}
end)

--- Balance of one account (the main one when `account` is left out).
---@param identifier string
---@param account integer|string|nil Position (1 = main) or account number.
---@return integer balance 0 if the account does not exist.
SafeExport('GetBalance', function(identifier, account)
	local target = ResolveOwnedAccount(identifier, account)
	return target and target.balance or 0
end)

--- All money of a player: the sum of every personal and savings account.
---@param identifier string
---@return integer total
SafeExport('GetTotalBalance', function(identifier)
	local total = 0

	for _, account in ipairs(ListWithIndex(identifier)) do
		total = total + account.balance
	end

	return total
end)

--- Credits an account. Recorded as a deposit with your note.
---@param identifier string
---@param amount integer
---@param note string?
---@param account integer|string|nil Position (1 = main) or account number.
---@return boolean ok
---@return string? errorReason
SafeExport('AddMoney', Credit)

--- Debits an account. Returns false (nothing moves) if the balance is
--- insufficient, the atomic guard in TbAccounts.Debit.
---@param identifier string
---@param amount integer
---@param note string?
---@param account integer|string|nil Position (1 = main) or account number.
---@return boolean ok
---@return string? errorReason 'insufficient_funds' | 'invalid_amount' | 'not_found' | 'savings_locked'
SafeExport('RemoveMoney', Debit)

--- Moves money from a player's default account to an account number or a server id.
---@param fromIdentifier string
---@param toNumber string|integer
---@param amount integer
---@param note string?
---@return boolean ok
---@return string? errorReason
SafeExport('TransferToNumber', function(fromIdentifier, toNumber, amount, note)
	local from = TbAccounts.GetOrCreateDefault(fromIdentifier)
	local to = TbAccounts.ResolveRecipient(toNumber)

	if not from or not to then
		return false, 'not_found'
	end

	return TbAccounts.Transfer(from.id, to.id, tonumber(amount) or 0, TbEnums.TransactionType.TRANSFER, fromIdentifier, note or 'External transfer')
end)

---@param number string
---@return TbAccount?
SafeExport('GetAccountByNumber', function(number)
	return TbAccounts.GetByNumber(number)
end)

--- Who an account belongs to. For a personal or savings account that is the
--- player (name from the online character or the ESX users table, `source`
--- only when online). A business account has no owner, it returns its job.
---@param number string Account number, for example '920-48271039'.
---@return { number: string, type: string, accountName: string, identifier: string?, name: string?, source: integer?, online: boolean, jobName: string? }?
SafeExport('GetAccountOwner', function(number)
	local account = type(number) == 'string' and TbAccounts.GetByNumber(number) or nil

	if not account then
		return nil
	end

	local result = {
		number = account.number,
		type = account.type,
		accountName = account.name,
		identifier = account.ownerIdentifier,
		jobName = account.jobName,
		online = false,
	}

	if account.ownerIdentifier then
		local source = TbFramework.GetSourceByIdentifier(account.ownerIdentifier)

		if source then
			result.source = source
			result.online = true
			result.name = TbFramework.GetName(source)
		else
			local ok, row = pcall(MySQL.single.await, 'SELECT firstname, lastname FROM users WHERE identifier = ?', { account.ownerIdentifier })

			if ok and row then
				result.name = (('%s %s'):format(row.firstname or '', row.lastname or '')):match('^%s*(.-)%s*$')
			end
		end
	end

	return result
end)

-- The same by server id, for scripts that only know the player's source.

---@param source integer
---@param account integer|string|nil
---@return integer balance
SafeExport('GetBalanceBySource', function(source, account)
	local identifier = IdentifierOf(source)
	local target = identifier and ResolveOwnedAccount(identifier, account)
	return target and target.balance or 0
end)

---@param source integer
---@return integer total
SafeExport('GetTotalBalanceBySource', function(source)
	local identifier = IdentifierOf(source)
	local total = 0

	for _, account in ipairs(identifier and ListWithIndex(identifier) or {}) do
		total = total + account.balance
	end

	return total
end)

---@param source integer
---@param amount integer
---@param note string?
---@param account integer|string|nil
---@return boolean ok
---@return string? errorReason
SafeExport('AddMoneyBySource', function(source, amount, note, account)
	return Credit(IdentifierOf(source), amount, note, account)
end)

---@param source integer
---@param amount integer
---@param note string?
---@param account integer|string|nil
---@return boolean ok
---@return string? errorReason
SafeExport('RemoveMoneyBySource', function(source, amount, note, account)
	return Debit(IdentifierOf(source), amount, note, account)
end)

--- The business account of a job, by job name ("mechanic") or by the
--- business name. Created on first use when the job exists in the framework.
---@param name string
---@return TbAccount?
SafeExport('GetSocietyAccountByName', function(name)
	if type(name) ~= 'string' or name == '' then
		return nil
	end

	local lowered = name:lower()
	local ok, rows = TbDb.SelectMany("SELECT * FROM tb_accounts WHERE type = 'society' AND deleted_at IS NULL")

	for _, row in ipairs(ok and rows or {}) do
		if (row.job_name and row.job_name:lower() == lowered) or row.name:lower() == lowered then
			return TbAccounts.RowToAccount(row)
		end
	end

	for jobName, job in pairs(TbFramework.GetJobs()) do
		if jobName:lower() == lowered or (job.label and job.label:lower() == lowered) then
			return TbAccounts.GetOrCreateJobAccount(jobName, job.label)
		end
	end

	return nil
end)

---@param jobName string
---@return integer balance
SafeExport('GetSocietyBalance', function(jobName)
	local account = TbAccounts.GetOrCreateJobAccount(jobName)
	return account and account.balance or 0
end)

---@param jobName string
---@param amount integer
---@param note string?
---@return boolean ok
SafeExport('AddSocietyMoney', function(jobName, amount, note)
	local account = TbAccounts.GetOrCreateJobAccount(jobName)
	return account ~= nil and TbAccounts.Credit(account.id, tonumber(amount) or 0, TbEnums.TransactionType.DEPOSIT, nil, note or 'External credit')
end)

---@param jobName string
---@param amount integer
---@param note string?
---@return boolean ok
SafeExport('RemoveSocietyMoney', function(jobName, amount, note)
	local account = TbAccounts.GetOrCreateJobAccount(jobName)
	return account ~= nil and TbAccounts.Debit(account.id, tonumber(amount) or 0, TbEnums.TransactionType.WITHDRAW, nil, note or 'External debit')
end)

--- Sends an invoice on behalf of any account (a job script billing a player,
--- for instance). Requires Config.Billing.Enabled.
---@param fromAccountId integer
---@param recipientInput string|integer Account number or server id.
---@param amount integer
---@param reason string?
---@return boolean ok
---@return string? errorReason
SafeExport('CreateInvoice', function(fromAccountId, recipientInput, amount, reason)
	local recipient = TbAccounts.ResolveRecipient(recipientInput)

	if not recipient then
		return false, 'recipient_not_found'
	end

	local ok, reasonKey = TbBilling.SendInvoice(tonumber(fromAccountId) or 0, recipient.id, tonumber(amount) or 0, reason, nil, nil)
	return ok, reasonKey
end)
