--- @module server.terminal.business
--- Aggregation for the terminal's Business tab, scoped to whichever business
--- the caller picked from their list (see server/society/permissions.lua's
--- ListBusinessesForPlayer, a player can have several). Access is
--- re-checked on every call, so being removed as staff mid-session takes
--- effect immediately.

local DEFAULT_LOOKBACK_DAYS = 30

TbSafe.Callback('tiltann_banking:terminal:listBusinesses', function(source)
	return TbSocietyPermissions.ListBusinessesForPlayer(source)
end)

--- One business's dashboard: balance, payout graph (including
--- admin_adjustment rows so a staff reset shows honestly), latest
--- transactions, open invoices, standing orders, and the caller's own
--- company card for it.
TbSafe.Callback('tiltann_banking:terminal:getBusiness', function(source, accountId)
	accountId = tonumber(accountId) or 0
	local role = TbSocietyPermissions.GetRole(source, accountId)
	local capabilities = TbSocietyPermissions.RoleToCapabilities(role)

	if not capabilities.view then
		return { allowed = false }
	end

	local account = TbAccounts.GetById(accountId)

	if not account or account.type ~= TbEnums.AccountType.SOCIETY then
		return { allowed = false }
	end

	-- The UI shows the job LABEL, never the raw job key.
	account.jobLabel = TbSocietyPermissions.GetJobLabel(account.jobName)

	local identifier = TbFramework.GetIdentifier(source)
	local sinceIso = os.date('!%Y-%m-%d %H:%M:%S', os.time() - DEFAULT_LOOKBACK_DAYS * 86400)
	local incoming, outgoing = {}, {}

	if Config.Billing.Enabled then
		incoming, outgoing = TbBilling.GetOpenForAccount(accountId)
	end

	local card = nil

	if Config.Cards.Enabled and identifier then
		for _, held in ipairs(TbCards.ListForHolder(identifier)) do
			if held.accountId == accountId then
				card = held
				break
			end
		end
	end

	return {
		allowed = true,
		account = account,
		role = role,
		capabilities = capabilities,
		days = TbTransactions.GetGroupedTotals(accountId, sinceIso),
		latestTransactions = TbTransactions.GetForAccount(accountId, 6, 0),
		openInvoices = { incoming = incoming, outgoing = outgoing },
		standingOrders = (Config.StandingOrders.Enabled and capabilities.withdraw) and TbStandingOrders.ListForAccount(accountId) or {},
		card = card,
		canHoldCard = Config.Cards.Enabled and (capabilities.deposit or capabilities.withdraw),
	}
end)

--- Hides a business statement up to now. Needs the delete capability (owner
--- level), the rows themselves stay in tb_transactions.
TbSafe.Callback('tiltann_banking:business:clearHistory', function(source, accountId)
	if not Config.Transactions.AllowClearHistory then
		return false, 'history_clear_disabled'
	end

	accountId = tonumber(accountId) or 0

	if not TbSocietyPermissions.GetCapabilities(source, accountId).delete then
		return false, 'society_no_permission'
	end

	local account = TbAccounts.GetById(accountId)

	if not account or account.type ~= TbEnums.AccountType.SOCIETY then
		return false, 'account_not_found'
	end

	if not TbTransactions.ClearHistory(accountId) then
		return false, 'internal_error'
	end

	TbLog('admin_actions', 'Business transaction history cleared', {
		{ name = 'Business', value = tostring(accountId) },
		{ name = 'By', value = TbFramework.GetIdentifier(source) or '?' },
	})

	return true
end)
