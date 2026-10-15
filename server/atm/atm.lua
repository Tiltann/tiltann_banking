--- @module server.atm.atm
--- Server side of the street ATM. With cards enabled, every action is keyed
--- by a card id: the PIN gate (`unlock`) opens the session, and each later
--- action re-validates the card (held by the caller, active, not locked) and
--- resolves the account from it, a personal card acts on its own account,
--- a company card on the business with that member's daily limit. With
--- cards disabled the ATM lists the player's own personal accounts instead
--- and actions are keyed by account id (identity-only auth).

TbAtm = {}

---@class TbAtmSession
---@field cardId integer?
---@field account TbAccount
---@field isCompany boolean
---@field dailyLimit integer
---@field withdrawnToday integer
---@field quickWithdraw integer[]
---@field transactions TbTransaction[]

--- Resolves what an ATM action operates on from the client's key.
---@param source integer
---@param key { cardId: integer?, accountId: integer? }
---@return TbAccount? account
---@return string? errorReason
---@return boolean isCompany
local function ResolveTarget(source, key)
	-- The key comes straight from the NUI, anything but a table is junk.
	key = type(key) == 'table' and key or {}

	local identifier = TbFramework.GetIdentifier(source)

	if not identifier then
		return nil, 'atm_no_card', false
	end

	if Config.Cards.Enabled then
		local card, reason = TbCards.GetUsable(identifier, tonumber(key.cardId) or 0)

		if not card then
			return nil, reason, false
		end

		local account = TbAccounts.GetById(card.account_id)

		if not account then
			return nil, 'account_not_found', false
		end

		return account, nil, account.type == TbEnums.AccountType.SOCIETY
	end

	local account = TbAccounts.GetOwned(identifier, tonumber(key.accountId) or 0)

	if not account or account.type ~= TbEnums.AccountType.PERSONAL then
		return nil, 'account_not_found', false
	end

	return account, nil, false
end

--- Everything the ATM screen shows for one account.
---@param source integer
---@param account TbAccount
---@param isCompany boolean
---@param cardId integer?
---@return TbAtmSession
local function BuildSession(source, account, isCompany, cardId)
	local identifier = TbFramework.GetIdentifier(source)
	local dailyLimit, withdrawnToday

	if isCompany then
		dailyLimit = TbSocietyPermissions.GetCardDailyLimit(identifier, account.id)
		withdrawnToday = TbTransactions.GetTodaysWithdrawals(identifier, { account.id })
	else
		local ownedIds = {}

		for i, owned in ipairs(TbAccounts.ListForPlayer(identifier)) do
			ownedIds[i] = owned.id
		end

		dailyLimit = Config.Limits.DailyWithdrawMax
		withdrawnToday = TbTransactions.GetTodaysWithdrawals(identifier, ownedIds)
	end

	return {
		cardId = cardId,
		account = TbAccounts.GetById(account.id) or account,
		isCompany = isCompany,
		dailyLimit = dailyLimit,
		withdrawnToday = withdrawnToday,
		quickWithdraw = Config.Atm.QuickWithdraw,
	}
end

--- What the ATM screen opens with: the cards to pick from, or (cards
--- disabled) the personal accounts to pick from.
TbSafe.Callback('tiltann_banking:atm:open', function(source)
	local identifier = TbFramework.GetIdentifier(source)

	if not identifier then
		return { cardsEnabled = Config.Cards.Enabled, cards = {}, accounts = {} }
	end

	if Config.Cards.Enabled then
		return { cardsEnabled = true, cards = TbCards.ListForHolder(identifier), accounts = {} }
	end

	local accounts = {}

	for _, account in ipairs(TbAccounts.ListForPlayer(identifier)) do
		if account.type == TbEnums.AccountType.PERSONAL then
			accounts[#accounts + 1] = account
		end
	end

	return { cardsEnabled = false, cards = {}, accounts = accounts }
end)

--- The PIN gate. On success returns the full session so the NUI never
--- needs a second round trip before showing the balance.
TbSafe.Callback('tiltann_banking:atm:unlock', function(source, cardId, pin)
	local identifier = TbFramework.GetIdentifier(source)

	if not identifier then
		return { ok = false, errorKey = 'atm_no_card' }
	end

	local ok, errorKey, accountId = TbCards.VerifyPin(identifier, tonumber(cardId) or 0, tostring(pin))

	if not ok then
		return { ok = false, errorKey = errorKey }
	end

	local account = TbAccounts.GetById(accountId)

	if not account then
		return { ok = false, errorKey = 'account_not_found' }
	end

	return { ok = true, session = BuildSession(source, account, account.type == TbEnums.AccountType.SOCIETY, tonumber(cardId)) }
end)

--- Session refresh (after an action, or the cards-disabled open path).
TbSafe.Callback('tiltann_banking:atm:getSession', function(source, key)
	local account, errorKey, isCompany = ResolveTarget(source, key)

	if not account then
		return { ok = false, errorKey = errorKey }
	end

	return { ok = true, session = BuildSession(source, account, isCompany, type(key) == 'table' and tonumber(key.cardId) or nil) }
end)

TbSafe.Callback('tiltann_banking:atm:withdraw', function(source, key, amount)
	local account, errorKey, isCompany = ResolveTarget(source, key)

	if not account then
		return false, errorKey
	end

	amount = tonumber(amount) or 0

	if isCompany then
		local identifier = TbFramework.GetIdentifier(source)
		return TbSocietyActions.Withdraw(source, account.id, amount, TbSocietyPermissions.GetCardDailyLimit(identifier, account.id))
	end

	return TbPersonal.WithdrawCash(source, account.id, amount)
end)

TbSafe.Callback('tiltann_banking:atm:deposit', function(source, key, amount)
	local account, errorKey, isCompany = ResolveTarget(source, key)

	if not account then
		return false, errorKey
	end

	amount = tonumber(amount) or 0

	if isCompany then
		return TbSocietyActions.Deposit(source, account.id, amount)
	end

	return TbPersonal.DepositCash(source, account.id, amount)
end)
