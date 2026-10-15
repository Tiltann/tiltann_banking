--- @module server.terminal.personal
--- Aggregation for the terminal's Personal tab, one callback gathers
--- everything the NUI needs (accounts, total, week graph, latest
--- transactions, open invoices, loan, cards, standing orders) in a single
--- round trip. No card gate: standing at the in-branch terminal is treated
--- as identity enough. Each optional section is included only when its
--- feature is on, so the NUI never special-cases a disabled module.

--- Config.Loans.Presets, minus anything the server would refuse anyway, so
--- the UI never offers a button that cannot work.
---@return integer[]
local function LoanPresets()
	if not Config.Loans.Enabled then
		return {}
	end

	local presets = {}

	for _, amount in ipairs(Config.Loans.Presets or {}) do
		if amount >= (Config.Loans.MinLoanAmount or 0) and amount <= Config.Loans.MaxLoanAmount then
			presets[#presets + 1] = amount
		end
	end

	return presets
end

---@param source integer
---@return table overview
TbSafe.Callback('tiltann_banking:terminal:getPersonal', function(source)
	local identifier = TbFramework.GetIdentifier(source)

	if not identifier then
		return { allowed = false }
	end

	local accounts = TbAccounts.ListForPlayer(identifier)

	if #accounts == 0 then
		local created = TbAccounts.GetOrCreateDefault(identifier)

		if not created then
			return { allowed = false }
		end

		accounts = TbAccounts.ListForPlayer(identifier)
	end

	local accountIds, totalBalance = {}, 0

	for i, account in ipairs(accounts) do
		accountIds[i] = account.id
		totalBalance = totalBalance + account.balance
	end

	local openInvoices = Config.Billing.Enabled and TbBilling.GetOpenAcross(accountIds) or {}

	return {
		allowed = true,
		accounts = accounts,
		totalBalance = totalBalance,
		week = TbTransactions.GetWeekSummary(accountIds),
		latestTransactions = TbTransactions.GetLatestAcross(accountIds, 6),
		openInvoices = openInvoices,
		loan = Config.Loans.Enabled and TbLoans.GetActive(identifier) or nil,
		loanHistory = Config.Loans.Enabled and TbLoans.ListHistory(identifier, 10) or {},
		cards = Config.Cards.Enabled and TbCards.ListForHolder(identifier) or {},
		standingOrders = Config.StandingOrders.Enabled and TbStandingOrders.ListAcross(accountIds) or {},
		limits = {
			maxAccounts = Config.Accounts.Max,
			newAccountPrice = Config.Accounts.NewAccountPrice,
			feeToBalance = Config.Accounts.FeeToBalance or 0,
			maxSavings = Config.Savings.Enabled and Config.Savings.MaxSavingsAccounts or 0,
			savingsPrice = Config.Savings.NewAccountPrice,
			savingsRate = Config.Savings.InterestRate,
			savingsIntervalSeconds = Config.Savings.IntervalSeconds,
			savingsLockSeconds = Config.Savings.WithdrawLockSeconds or 0,
			maxLoan = Config.Loans.MaxLoanAmount,
			minLoan = Config.Loans.MinLoanAmount or 0,
			loanPresets = LoanPresets(),
			minOrderInterval = Config.StandingOrders.MinIntervalSeconds,
		},
	}
end)

--- Statement page for any account the caller may view: own accounts, or a
--- business their role lets them see.
TbSafe.Callback('tiltann_banking:terminal:getTransactions', function(source, accountId, offset, filters)
	accountId = tonumber(accountId) or 0
	local identifier = TbFramework.GetIdentifier(source)
	local account = identifier and TbAccounts.GetById(accountId)

	if not account then
		return {}
	end

	local allowed

	if account.type == TbEnums.AccountType.SOCIETY then
		allowed = TbSocietyPermissions.GetCapabilities(source, accountId).view
	else
		allowed = account.ownerIdentifier == identifier
	end

	if not allowed then
		return {}
	end

	return TbTransactions.GetForAccount(accountId, 25, tonumber(offset) or 0, type(filters) == 'table' and filters or nil)
end)

TbSafe.Callback('tiltann_banking:personal:createAccount', function(source, name, accountType)
	local identifier = TbFramework.GetIdentifier(source)

	if not identifier then
		return false, 'account_not_found'
	end

	local ok, errorKey = TbPersonal.CreateAccount(identifier, name, accountType)
	return ok, errorKey
end)

TbSafe.Callback('tiltann_banking:personal:renameAccount', function(source, accountId, name)
	local identifier = TbFramework.GetIdentifier(source)

	if not identifier then
		return false, 'account_not_found'
	end

	return TbPersonal.RenameAccount(identifier, tonumber(accountId) or 0, name)
end)

TbSafe.Callback('tiltann_banking:personal:setDefault', function(source, accountId)
	local identifier = TbFramework.GetIdentifier(source)

	if not identifier then
		return false, 'account_not_found'
	end

	return TbPersonal.SetDefaultAccount(identifier, tonumber(accountId) or 0)
end)

TbSafe.Callback('tiltann_banking:personal:deleteAccount', function(source, accountId)
	local identifier = TbFramework.GetIdentifier(source)

	if not identifier then
		return false, 'account_not_found'
	end

	return TbPersonal.DeleteAccount(identifier, tonumber(accountId) or 0)
end)

TbSafe.Callback('tiltann_banking:personal:deposit', function(source, accountId, amount)
	return TbPersonal.DepositCash(source, tonumber(accountId) or 0, tonumber(amount) or 0)
end)

TbSafe.Callback('tiltann_banking:personal:withdraw', function(source, accountId, amount)
	return TbPersonal.WithdrawCash(source, tonumber(accountId) or 0, tonumber(amount) or 0)
end)

TbSafe.Callback('tiltann_banking:personal:transfer', function(source, fromAccountId, recipientInput, amount, note)
	return TbPersonal.Transfer(source, tonumber(fromAccountId) or 0, tostring(recipientInput or ''), tonumber(amount) or 0, note)
end)

--- Hides the caller's statement up to now (soft clear, nothing is deleted).
TbSafe.Callback('tiltann_banking:personal:clearHistory', function(source, accountId)
	if not Config.Transactions.AllowClearHistory then
		return false, 'history_clear_disabled'
	end

	accountId = tonumber(accountId) or 0
	local identifier = TbFramework.GetIdentifier(source)

	if not identifier or not TbAccounts.GetOwned(identifier, accountId) then
		return false, 'account_not_found'
	end

	if not TbTransactions.ClearHistory(accountId) then
		return false, 'internal_error'
	end

	TbLog('admin_actions', 'Transaction history cleared', {
		{ name = 'Account', value = tostring(accountId) },
		{ name = 'By', value = identifier },
	})

	return true
end)
