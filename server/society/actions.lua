--- @module server.society.actions
--- Cash in/out against a specific business the caller has access to (via
--- their job or explicit staff membership, see server/society/permissions.lua).
--- Capabilities are re-resolved for THIS account on every call: a player who
--- lost access between opening the terminal and clicking is re-checked
--- against their CURRENT standing, not whatever the UI was built for.

TbSocietyActions = {}

--- Player cash -> business account. Shared by the terminal's Business tab
--- and the ATM (company cards), see server/atm/atm.lua.
---@param source integer
---@param accountId integer
---@param amount integer
---@return boolean ok
---@return string? errorReason
function TbSocietyActions.Deposit(source, accountId, amount)
	amount = TbUtils.RoundMoney(amount)

	if amount < Config.Limits.MinTransactionAmount or amount > Config.Limits.MaxTransactionAmount then
		return false, 'tx_limit_exceeded'
	end

	if not TbSocietyPermissions.GetCapabilities(source, accountId).deposit then
		return false, 'society_no_permission'
	end

	local identifier = TbFramework.GetIdentifier(source)

	if not identifier or (TbFramework.GetCash(source) or 0) < amount then
		return false, 'tx_insufficient_cash'
	end

	local account = TbAccounts.GetById(accountId)

	if not account or account.type ~= TbEnums.AccountType.SOCIETY then
		return false, 'account_not_found'
	end

	if not TbFramework.RemoveCash(source, amount) then
		return false, 'tx_insufficient_cash'
	end

	if not TbAccounts.Credit(account.id, amount, TbEnums.TransactionType.DEPOSIT, identifier, ('Deposit (%s)'):format(TbFramework.GetName(source) or account.name)) then
		-- The cash is already gone, give it back instead of losing it.
		TbLogger.Error('society', 'deposit credit failed, cash returned', { account = account.id, amount = amount }, source)
		TbFramework.AddCash(source, amount)
		return false, 'tx_invalid_amount'
	end

	if TbLog then
		TbLog('deposits', 'Business deposit', {
			{ name = 'Business', value = account.name },
			{ name = 'By', value = identifier },
			{ name = 'Amount', value = tostring(amount) },
		})
	end

	return true, nil
end

--- Business account -> player cash. `dailyLimit`, when given, caps what
--- this player may take from this business per day (company cards at an
--- ATM), the terminal passes nil, trusting the role alone.
---@param source integer
---@param accountId integer
---@param amount integer
---@param dailyLimit integer?
---@return boolean ok
---@return string? errorReason
function TbSocietyActions.Withdraw(source, accountId, amount, dailyLimit)
	amount = TbUtils.RoundMoney(amount)

	if amount < Config.Limits.MinTransactionAmount or amount > Config.Limits.MaxTransactionAmount then
		return false, 'tx_limit_exceeded'
	end

	if not TbSocietyPermissions.GetCapabilities(source, accountId).withdraw then
		return false, 'society_no_permission'
	end

	local identifier = TbFramework.GetIdentifier(source)

	if not identifier then
		return false, 'account_not_found'
	end

	local account = TbAccounts.GetById(accountId)

	if not account or account.type ~= TbEnums.AccountType.SOCIETY then
		return false, 'account_not_found'
	end

	if dailyLimit and TbTransactions.GetTodaysWithdrawals(identifier, { accountId }) + amount > dailyLimit then
		return false, 'tx_daily_limit_exceeded'
	end

	local ok, reason = TbAccounts.Debit(account.id, amount, TbEnums.TransactionType.WITHDRAW, identifier, ('Withdrawal (%s)'):format(TbFramework.GetName(source) or account.name))

	if not ok then
		return false, reason == 'insufficient_funds' and 'tx_insufficient_funds' or 'tx_invalid_amount'
	end

	if not TbFramework.AddCash(source, amount) then
		-- The player vanished between the debit and the payout, put the money back.
		TbLogger.Error('society', 'cash payout failed, withdrawal reverted', { account = account.id, amount = amount }, source)
		TbAccounts.Credit(account.id, amount, TbEnums.TransactionType.DEPOSIT, identifier, 'Withdrawal reverted')
		return false, 'tx_invalid_amount'
	end

	if TbLog then
		TbLog('withdrawals', 'Business withdrawal', {
			{ name = 'Business', value = account.name },
			{ name = 'By', value = identifier },
			{ name = 'Amount', value = tostring(amount) },
		})
	end

	return true, nil
end

--- Renames a business, owners only.
---@param source integer
---@param accountId integer
---@param name string
---@return boolean ok
---@return string? errorReason
local function BusinessRename(source, accountId, name)
	local cleanName = TbUtils.CleanName(name, Config.Accounts.MaxNameLength)

	if not cleanName then
		return false, 'account_invalid_name'
	end

	if TbSocietyPermissions.GetRole(source, accountId) ~= TbEnums.Role.OWNER then
		return false, 'society_no_permission'
	end

	return TbAccounts.Rename(accountId, cleanName), nil
end

TbSafe.Callback('tiltann_banking:society:deposit', function(source, accountId, amount)
	return TbSocietyActions.Deposit(source, tonumber(accountId) or 0, tonumber(amount) or 0)
end)

TbSafe.Callback('tiltann_banking:society:withdraw', function(source, accountId, amount)
	return TbSocietyActions.Withdraw(source, tonumber(accountId) or 0, tonumber(amount) or 0, nil)
end)

TbSafe.Callback('tiltann_banking:society:rename', function(source, accountId, name)
	return BusinessRename(source, tonumber(accountId) or 0, name)
end)
