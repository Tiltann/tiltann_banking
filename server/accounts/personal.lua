--- @module server.accounts.personal
--- Everything a player does with their own accounts: create/rename/delete/
--- set-default (pefcl-style, up to Config.Accounts.Max), cash in/out, and
--- transfers from any account they own. Ownership is re-checked on every
--- call via TbAccounts.GetOwned, nothing about which account a request
--- targets is trusted from the client.

TbPersonal = {}

--- Translates an accounts.lua Debit/Transfer failure into the errorKey the
--- NUI shows (i18n `error.<key>`).
---@param reason string?
---@return string errorKey
function TbPersonal.MapMoveError(reason)
	if reason == 'insufficient_funds' then
		return 'tx_insufficient_funds'
	elseif reason == 'savings_locked' then
		return 'savings_locked'
	end

	return 'tx_invalid_amount'
end

--- Counts a player's live accounts of one type.
---@param identifier string
---@param accountType TbAccountType
---@return integer
local function CountAccounts(identifier, accountType)
	local ok, row = TbDb.SelectOne(
		'SELECT COUNT(*) AS count FROM tb_accounts WHERE owner_identifier = ? AND type = ? AND deleted_at IS NULL',
		{ identifier, accountType }
	)

	return (ok and row and row.count) or 0
end

--- Creates an extra personal or savings account, charging the fee from the
--- player's default account.
---@param identifier string
---@param name string
---@param accountType 'personal'|'savings'
---@return boolean ok
---@return string? errorReason
---@return TbAccount? account
function TbPersonal.CreateAccount(identifier, name, accountType)
	local cleanName = TbUtils.CleanName(name, Config.Accounts.MaxNameLength)

	if not cleanName then
		return false, 'account_invalid_name'
	end

	local isSavings = accountType == TbEnums.AccountType.SAVINGS

	if isSavings then
		if not Config.Savings.Enabled then
			return false, 'savings_disabled'
		end

		if CountAccounts(identifier, TbEnums.AccountType.SAVINGS) >= Config.Savings.MaxSavingsAccounts then
			return false, 'account_limit_reached'
		end
	elseif accountType == TbEnums.AccountType.PERSONAL then
		if CountAccounts(identifier, TbEnums.AccountType.PERSONAL) >= Config.Accounts.Max then
			return false, 'account_limit_reached'
		end
	else
		return false, 'account_invalid_type'
	end

	local defaultAccount = TbAccounts.GetOrCreateDefault(identifier)

	if not defaultAccount then
		return false, 'account_not_found'
	end

	local price = isSavings and Config.Savings.NewAccountPrice or Config.Accounts.NewAccountPrice

	if price > 0 then
		local paid = TbAccounts.Debit(defaultAccount.id, price, TbEnums.TransactionType.ACCOUNT_FEE, identifier, 'New account fee')

		if not paid then
			return false, 'tx_insufficient_funds'
		end
	end

	-- part of the opening fee goes straight onto the new account
	local startBalance = isSavings and Config.Savings.StartBalance or Config.Accounts.StartBalance.Other
	local feeBack = math.floor(price * (Config.Accounts.FeeToBalance or 0))

	local account = TbAccounts.Create({
		type = accountType,
		ownerIdentifier = identifier,
		name = cleanName,
		balance = startBalance + feeBack,
		isDefault = false,
		interestRate = isSavings and Config.Savings.InterestRate or nil,
	})

	if not account then
		-- Refund rather than leaving the player charged for nothing.
		if price > 0 then
			TbAccounts.Credit(defaultAccount.id, price, TbEnums.TransactionType.ACCOUNT_FEE, identifier, 'New account fee refund')
		end

		return false, 'account_not_found'
	end

	if TbLog then
		TbLog('admin_actions', 'Account created', {
			{ name = 'Owner', value = identifier },
			{ name = 'Type', value = accountType },
			{ name = 'Number', value = account.number },
		})
	end

	return true, nil, account
end

---@param identifier string
---@param accountId integer
---@param name string
---@return boolean ok
---@return string? errorReason
function TbPersonal.RenameAccount(identifier, accountId, name)
	local cleanName = TbUtils.CleanName(name, Config.Accounts.MaxNameLength)

	if not cleanName then
		return false, 'account_invalid_name'
	end

	if not TbAccounts.GetOwned(identifier, accountId) then
		return false, 'account_not_found'
	end

	return TbAccounts.Rename(accountId, cleanName), nil
end

---@param identifier string
---@param accountId integer
---@return boolean ok
---@return string? errorReason
function TbPersonal.SetDefaultAccount(identifier, accountId)
	local account = TbAccounts.GetOwned(identifier, accountId)

	if not account then
		return false, 'account_not_found'
	end

	if account.type ~= TbEnums.AccountType.PERSONAL then
		return false, 'account_savings_not_default'
	end

	return TbAccounts.SetDefault(identifier, accountId), nil
end

--- Deletes a non-default account after sweeping its balance into the
--- default one (pefcl's "funds will be transferred to default account").
---@param identifier string
---@param accountId integer
---@return boolean ok
---@return string? errorReason
function TbPersonal.DeleteAccount(identifier, accountId)
	local account = TbAccounts.GetOwned(identifier, accountId)

	if not account then
		return false, 'account_not_found'
	end

	if account.isDefault then
		return false, 'account_cannot_delete_default'
	end

	local defaultAccount = TbAccounts.GetOrCreateDefault(identifier)

	if not defaultAccount then
		return false, 'account_not_found'
	end

	if account.balance > 0 then
		local moved, reason = TbAccounts.Transfer(account.id, defaultAccount.id, account.balance, TbEnums.TransactionType.TRANSFER,
			identifier, ('Closed account %s'):format(account.number))

		if not moved then
			return false, reason == 'savings_locked' and 'savings_locked' or 'account_close_failed'
		end
	end

	-- A savings account being closed must stop its interest and any orders.
	TbDb.Update('UPDATE tb_standing_orders SET active = 0 WHERE from_account_id = ?', { accountId })
	TbDb.Update("UPDATE tb_cards SET status = 'lost' WHERE account_id = ?", { accountId })

	return TbAccounts.SoftDelete(accountId), nil
end

--- Cash -> account. The account may be any the player owns (a savings
--- account can be topped up at the terminal). Tax applies on deposit when
--- enabled: cash is reduced by the full amount, only the net lands.
---@param source integer
---@param accountId integer
---@param amount integer
---@return boolean ok
---@return string? errorReason
function TbPersonal.DepositCash(source, accountId, amount)
	amount = TbUtils.RoundMoney(amount)

	if amount < Config.Limits.MinTransactionAmount or amount > Config.Limits.MaxTransactionAmount then
		return false, 'tx_limit_exceeded'
	end

	local identifier = TbFramework.GetIdentifier(source)
	local account = identifier and TbAccounts.GetOwned(identifier, accountId)

	if not account then
		return false, 'account_not_found'
	end

	if not TbFramework.RemoveCash(source, amount) then
		return false, 'tx_insufficient_cash'
	end

	local netAmount = TbTax.Apply(identifier, account.id, amount, 'deposit')

	if not TbAccounts.Credit(account.id, netAmount, TbEnums.TransactionType.DEPOSIT, identifier, 'Cash deposit') then
		-- The cash is already gone, give it back instead of losing it.
		TbLogger.Error('personal', 'deposit credit failed, cash returned', { identifier = identifier, account = account.id, amount = amount }, source)
		TbFramework.AddCash(source, amount)
		return false, 'tx_invalid_amount'
	end

	if TbLog then
		TbLog('deposits', 'Deposit', {
			{ name = 'Identifier', value = identifier },
			{ name = 'Account', value = account.number },
			{ name = 'Amount', value = tostring(amount) },
		})
	end

	return true, nil
end

--- Account -> cash. Enforces Config.Limits.DailyWithdrawMax across all the
--- player's own accounts. Savings accounts can't be withdrawn from at an ATM
--- (no card) but can at the terminal, the ATM module gates that itself.
---@param source integer
---@param accountId integer
---@param amount integer
---@return boolean ok
---@return string? errorReason
function TbPersonal.WithdrawCash(source, accountId, amount)
	amount = TbUtils.RoundMoney(amount)

	if amount < Config.Limits.MinTransactionAmount or amount > Config.Limits.MaxTransactionAmount then
		return false, 'tx_limit_exceeded'
	end

	local identifier = TbFramework.GetIdentifier(source)
	local account = identifier and TbAccounts.GetOwned(identifier, accountId)

	if not account then
		return false, 'account_not_found'
	end

	local ownedIds = {}

	for i, owned in ipairs(TbAccounts.ListForPlayer(identifier)) do
		ownedIds[i] = owned.id
	end

	if TbTransactions.GetTodaysWithdrawals(identifier, ownedIds) + amount > Config.Limits.DailyWithdrawMax then
		return false, 'tx_daily_limit_exceeded'
	end

	local ok, reason = TbAccounts.Debit(account.id, amount, TbEnums.TransactionType.WITHDRAW, identifier, 'Cash withdrawal')

	if not ok then
		return false, TbPersonal.MapMoveError(reason)
	end

	-- Withdraw tax (Config.Tax.ApplyOn.withdraw): the account loses the full
	-- amount, the player receives the net.
	local netAmount = TbTax.Apply(identifier, account.id, amount, 'withdraw')

	if not TbFramework.AddCash(source, netAmount) then
		-- The player vanished between the debit and the payout, put the money back.
		TbLogger.Error('personal', 'cash payout failed, withdrawal reverted', { identifier = identifier, account = account.id, amount = netAmount }, source)
		TbAccounts.Credit(account.id, netAmount, TbEnums.TransactionType.DEPOSIT, identifier, 'Withdrawal reverted')
		return false, 'tx_invalid_amount'
	end

	if TbLog then
		TbLog('withdrawals', 'Withdrawal', {
			{ name = 'Identifier', value = identifier },
			{ name = 'Account', value = account.number },
			{ name = 'Amount', value = tostring(amount) },
		})
	end

	return true, nil
end

--- Transfers from an account the player owns to any account number or
--- identifier (their own other accounts included). Tax on transfer applies
--- only when the recipient isn't the same player, so shuffling money between
--- your own accounts is never taxed twice.
---@param source integer
---@param fromAccountId integer
---@param recipientInput string
---@param amount integer
---@param note string?
---@return boolean ok
---@return string? errorReason
function TbPersonal.Transfer(source, fromAccountId, recipientInput, amount, note)
	amount = TbUtils.RoundMoney(amount)

	if amount < Config.Limits.MinTransactionAmount or amount > Config.Limits.MaxTransactionAmount then
		return false, 'tx_limit_exceeded'
	end

	local identifier = TbFramework.GetIdentifier(source)
	local fromAccount = identifier and TbAccounts.GetOwned(identifier, fromAccountId)

	if not fromAccount then
		return false, 'account_not_found'
	end

	local recipient = TbAccounts.ResolveRecipient(recipientInput)

	if not recipient then
		return false, 'tx_recipient_not_found'
	end

	if recipient.id == fromAccount.id then
		return false, 'tx_same_account'
	end

	local isOwnAccount = recipient.ownerIdentifier == identifier

	-- The sender pays the gross amount (tax included), so check that up front
	-- and before any tax is collected.
	if not isOwnAccount and fromAccount.balance < amount then
		return false, 'tx_insufficient_funds'
	end

	local netAmount, taxAmount = amount, 0

	if not isOwnAccount then
		netAmount, taxAmount = TbTax.Apply(identifier, fromAccount.id, amount, 'transfer')
	end

	local ok, reason = TbAccounts.Transfer(fromAccount.id, recipient.id, netAmount, TbEnums.TransactionType.TRANSFER,
		identifier, TbUtils.CleanName(note, 100) or 'Transfer')

	if not ok then
		return false, TbPersonal.MapMoveError(reason)
	end

	if taxAmount and taxAmount > 0 then
		-- Tax was credited to the treasury, the sender still owes it.
		local taxPaid = TbAccounts.Debit(fromAccount.id, taxAmount, TbEnums.TransactionType.TAX, identifier, 'Transfer tax')

		if not taxPaid then
			TbLogger.Error('personal', 'transfer tax could not be debited from the sender', { account = fromAccount.id, tax = taxAmount }, source)
		end
	end

	if TbLog then
		TbLog('transfers', 'Transfer', {
			{ name = 'From', value = fromAccount.number },
			{ name = 'To', value = recipient.number },
			{ name = 'Amount', value = tostring(amount) },
		})
	end

	return true, nil
end
