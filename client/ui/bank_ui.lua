--- @module client.ui.bank_ui
--- The single NUI both entry points share, in two modes:
---
--- 'atm' (client/atm.lua, TbOpenAtm): a small card-gated screen, pick a
---   card, enter its PIN, then balance / quick withdraw / deposit /
---   transfer on that card's account. No tabs, no Business dashboard.
--- 'terminal' (client/terminal.lua, TbOpenTerminal): the tablet Main UI
---   with Personal and Business tabs. No card needed, standing at the
---   in-branch terminal is treated as identity enough.
---
--- Every NUI callback is a thin wrapper around a server lib.callback: this
--- file owns none of the business logic, only the client<->NUI<->server
--- plumbing. Two helpers below cover the two result shapes servers return.

local nuiOpen = false

local function CloseUI()
	if not nuiOpen then
		return
	end

	nuiOpen = false
	SetNuiFocus(false, false)
	SendNUIMessage({ action = 'close' })
end

local translationCache = nil

--- Every language file in locales/ui/, read once.
---@return table<string, table<string, string>>
local function LoadTranslations()
	if translationCache then
		return translationCache
	end

	local loaded = {}

	for _, code in ipairs(Config.UI.Languages) do
		local raw = LoadResourceFile(GetCurrentResourceName(), ('locales/ui/%s.json'):format(code))
		local ok, decoded = pcall(json.decode, raw or '')

		if ok and type(decoded) == 'table' then
			loaded[code] = decoded
		else
			TbLogger.Warn('ui', 'could not read the UI language file', { language = code })
		end
	end

	if next(loaded) == nil then
		TbLogger.Error('ui', 'no UI language file could be read, check that locales/ui/*.json exist and are listed in fxmanifest.lua files')
		return loaded
	end

	translationCache = loaded
	return loaded
end

--- Common payload fields every open message carries.
---@return table
local function BasePayload()
	return {
		action = 'open',
		colors = Config.UI.Colors,
		currencySymbol = Config.UI.CurrencySymbol,
		defaultLanguage = Config.UI.DefaultLanguage,
		translations = LoadTranslations(),
		features = {
			cardsEnabled = Config.Cards.Enabled,
			savingsEnabled = Config.Savings.Enabled,
			loansEnabled = Config.Loans.Enabled,
			billingEnabled = Config.Billing.Enabled,
			standingOrdersEnabled = Config.StandingOrders.Enabled,
			taxEnabled = Config.Tax.Enabled,
			clearHistoryEnabled = Config.Transactions.AllowClearHistory,
		},
	}
end

--- Shows the UI with a fully built payload. Focus is only taken once the
--- payload is ready, so a failed server call never leaves the player stuck
--- with NUI focus and no UI.
---@param payload table
local function Present(payload)
	nuiOpen = true
	SetNuiFocus(true, true)
	SendNUIMessage(payload)
	TbLogger.Debug('ui', 'opened', { mode = payload.mode })
end

-- Set while an open request is in flight, so a double press of the key does
-- not stack two server round trips and two UIs.
local opening = false

--- Opens the ATM screen.
function TbOpenAtm()
	if nuiOpen or opening then
		return
	end

	opening = true

	local ok = TbSafe.Run('ui:openAtm', function()
		local atm = lib.callback.await('tiltann_banking:atm:open', false)

		if not atm then
			error('atm:open returned nothing, server callback failed or timed out')
		end

		local payload = BasePayload()

		payload.mode = 'atm'
		payload.atm = atm
		Present(payload)
	end)

	opening = false

	if not ok then
		lib.notify({ type = 'error', description = locale('ui_open_failed') })
	end
end

--- Opens the bank terminal. Refuses (plain notification, no NUI) only if the
--- player's own account can't even be resolved, everyone else gets the
--- Personal tab, and the Business tab if they have any business.
function TbOpenTerminal()
	if nuiOpen or opening then
		return
	end

	opening = true

	local ok = TbSafe.Run('ui:openTerminal', function()
		local personal = lib.callback.await('tiltann_banking:terminal:getPersonal', false)

		if not personal or not personal.allowed then
			TbLogger.Warn('ui', 'terminal refused, personal overview not available', { allowed = personal and personal.allowed })
			lib.notify({ type = 'error', description = locale('terminal_no_access') })
			return
		end

		local businesses = lib.callback.await('tiltann_banking:terminal:listBusinesses', false)
		local business = nil

		if type(businesses) ~= 'table' then
			businesses = {}
		end

		if #businesses > 0 then
			business = lib.callback.await('tiltann_banking:terminal:getBusiness', false, businesses[1].accountId)
		end

		local payload = BasePayload()

		payload.mode = 'terminal'
		payload.personal = personal
		payload.businesses = businesses
		payload.business = business
		Present(payload)
	end)

	opening = false

	if not ok then
		lib.notify({ type = 'error', description = locale('ui_open_failed') })
	end
end

--- Whether the bank UI is on screen.
---@return boolean
function TbIsUiOpen()
	return nuiOpen
end

--- Closes the bank UI if it is open.
function TbCloseUi()
	CloseUI()
end

--- Tells an open UI to reload its data, used when a balance changed behind it.
function TbRefreshUI()
	if nuiOpen then
		SendNUIMessage({ action = 'refresh' })
	end
end

--- Opens the billing menu: send a bill from a personal account or a business,
--- and pay the ones you received.
function TbOpenBilling()
	local ok = TbSafe.Run('ui:openBilling', function()
		if nuiOpen then
			return
		end

		local accounts = lib.callback.await('tiltann_banking:billing:getSenders', false)

		if type(accounts) ~= 'table' or #accounts == 0 then
			lib.notify({ type = 'error', description = locale('billing_no_access') })
			return
		end

		local payload = BasePayload()

		payload.mode = 'billing'
		payload.accounts = accounts
		payload.billing = { maxSharePercent = Config.Billing.MaxPersonalSharePercent, nearbyRadius = Config.Billing.NearbyRadius }
		Present(payload)
	end)

	if not ok then
		lib.notify({ type = 'error', description = locale('ui_open_failed') })
	end
end

TbSafe.Nui('tiltann_banking:ui:close', function(_, cb)
	CloseUI()
	cb({ ok = true })
end)

-- Never leave the cursor stuck on screen when the resource stops or restarts.
AddEventHandler('onResourceStop', function(resource)
	if resource == GetCurrentResourceName() and nuiOpen then
		SetNuiFocus(false, false)
	end
end)

-- Escape closes the UI in addition to the React side's close button. Polls
-- every frame only while open; sleeps otherwise so it costs nothing.
CreateThread(function()
	while true do
		Wait(nuiOpen and 0 or 500)

		if nuiOpen and IsControlJustPressed(0, 322) then -- INPUT_FRONTEND_PAUSE / Escape
			CloseUI()
		end
	end
end)

--- Registers an NUI callback whose server callback returns ONE value (a
--- table or list) that the NUI wants as-is.
---@param nuiName string
---@param serverName string
---@param argKeys string[] Fields of the NUI's data object, in server-argument order.
local function ForwardResult(nuiName, serverName, argKeys)
	TbSafe.Nui(nuiName, function(data, cb)
		local args = {}

		for i, key in ipairs(argKeys) do
			args[i] = data and data[key] or nil
		end

		local result = lib.callback.await(serverName, false, table.unpack(args, 1, #argKeys))

		if result == false then
			-- TbSafe.Callback's error boundary answered `false, 'internal_error'`.
			TbLogger.Warn('nui', ('%s failed on the server'):format(serverName))
			cb({ ok = false, errorKey = 'internal_error' })
			return
		end

		cb(result)
	end)
end

--- Registers an NUI callback whose server callback returns the
--- (ok, errorKey, extra) triple every mutating action uses.
---@param nuiName string
---@param serverName string
---@param argKeys string[]
local function ForwardAction(nuiName, serverName, argKeys)
	TbSafe.Nui(nuiName, function(data, cb)
		local args = {}

		for i, key in ipairs(argKeys) do
			args[i] = data and data[key] or nil
		end

		local ok, errorKey, extra = lib.callback.await(serverName, false, table.unpack(args, 1, #argKeys))
		cb({ ok = ok == true, errorKey = errorKey, value = extra })
	end)
end

-- ATM ------------------------------------------------------------------------
ForwardResult('tiltann_banking:ui:atm:unlock', 'tiltann_banking:atm:unlock', { 'cardId', 'pin' })
ForwardResult('tiltann_banking:ui:atm:getSession', 'tiltann_banking:atm:getSession', { 'key' })
ForwardAction('tiltann_banking:ui:atm:withdraw', 'tiltann_banking:atm:withdraw', { 'key', 'amount' })
ForwardAction('tiltann_banking:ui:atm:deposit', 'tiltann_banking:atm:deposit', { 'key', 'amount' })

-- Personal -------------------------------------------------------------------
ForwardResult('tiltann_banking:ui:personal:get', 'tiltann_banking:terminal:getPersonal', {})
ForwardResult('tiltann_banking:ui:transactions', 'tiltann_banking:terminal:getTransactions', { 'accountId', 'offset', 'filters' })
ForwardAction('tiltann_banking:ui:personal:clearHistory', 'tiltann_banking:personal:clearHistory', { 'accountId' })
ForwardAction('tiltann_banking:ui:personal:createAccount', 'tiltann_banking:personal:createAccount', { 'name', 'accountType' })
ForwardAction('tiltann_banking:ui:personal:renameAccount', 'tiltann_banking:personal:renameAccount', { 'accountId', 'name' })
ForwardAction('tiltann_banking:ui:personal:setDefault', 'tiltann_banking:personal:setDefault', { 'accountId' })
ForwardAction('tiltann_banking:ui:personal:deleteAccount', 'tiltann_banking:personal:deleteAccount', { 'accountId' })
ForwardAction('tiltann_banking:ui:personal:deposit', 'tiltann_banking:personal:deposit', { 'accountId', 'amount' })
ForwardAction('tiltann_banking:ui:personal:withdraw', 'tiltann_banking:personal:withdraw', { 'accountId', 'amount' })
ForwardAction('tiltann_banking:ui:personal:transfer', 'tiltann_banking:personal:transfer', { 'fromAccountId', 'recipient', 'amount', 'note' })

-- Loans ----------------------------------------------------------------------
ForwardAction('tiltann_banking:ui:loans:request', 'tiltann_banking:loans:request', { 'amount' })
ForwardAction('tiltann_banking:ui:loans:repay', 'tiltann_banking:loans:repay', { 'amount' })

-- Tax page
ForwardResult('tiltann_banking:ui:tax:get', 'tiltann_banking:tax:getOverview', {})

-- Invoices -------------------------------------------------------------------
ForwardResult('tiltann_banking:ui:billing:getOpen', 'tiltann_banking:billing:getOpen', { 'accountId' })
ForwardAction('tiltann_banking:ui:billing:send', 'tiltann_banking:billing:send', { 'fromAccountId', 'recipient', 'amount', 'reason', 'sharePercent' })
ForwardResult('tiltann_banking:ui:billing:getNearby', 'tiltann_banking:billing:getNearby', {})
ForwardAction('tiltann_banking:ui:billing:pay', 'tiltann_banking:billing:pay', { 'invoiceId' })
ForwardAction('tiltann_banking:ui:billing:decline', 'tiltann_banking:billing:decline', { 'invoiceId' })

-- Standing orders ------------------------------------------------------------
ForwardResult('tiltann_banking:ui:orders:list', 'tiltann_banking:orders:list', { 'accountId' })
ForwardAction('tiltann_banking:ui:orders:create', 'tiltann_banking:orders:create', { 'fromAccountId', 'toNumber', 'amount', 'intervalSeconds', 'note' })
ForwardAction('tiltann_banking:ui:orders:cancel', 'tiltann_banking:orders:cancel', { 'orderId' })

-- Cards ----------------------------------------------------------------------
ForwardResult('tiltann_banking:ui:cards:list', 'tiltann_banking:cards:list', {})
ForwardAction('tiltann_banking:ui:cards:request', 'tiltann_banking:cards:request', { 'accountId' })
ForwardAction('tiltann_banking:ui:cards:setPin', 'tiltann_banking:cards:setPin', { 'cardId', 'pin' })
ForwardAction('tiltann_banking:ui:cards:toggleLock', 'tiltann_banking:cards:toggleLock', { 'cardId' })
ForwardAction('tiltann_banking:ui:cards:reportLost', 'tiltann_banking:cards:reportLost', { 'cardId' })
ForwardAction('tiltann_banking:ui:cards:delete', 'tiltann_banking:cards:delete', { 'cardId' })

-- Business -------------------------------------------------------------------
ForwardResult('tiltann_banking:ui:business:list', 'tiltann_banking:terminal:listBusinesses', {})
ForwardResult('tiltann_banking:ui:business:get', 'tiltann_banking:terminal:getBusiness', { 'accountId' })
ForwardAction('tiltann_banking:ui:business:deposit', 'tiltann_banking:society:deposit', { 'accountId', 'amount' })
ForwardAction('tiltann_banking:ui:business:withdraw', 'tiltann_banking:society:withdraw', { 'accountId', 'amount' })
ForwardAction('tiltann_banking:ui:business:clearHistory', 'tiltann_banking:business:clearHistory', { 'accountId' })
ForwardAction('tiltann_banking:ui:business:rename', 'tiltann_banking:society:rename', { 'accountId', 'name' })
ForwardResult('tiltann_banking:ui:business:listMembers', 'tiltann_banking:society:listMembers', { 'accountId' })
ForwardAction('tiltann_banking:ui:business:addMember', 'tiltann_banking:society:addMember', { 'accountId', 'serverId', 'role' })
ForwardAction('tiltann_banking:ui:business:setMemberRole', 'tiltann_banking:society:setMemberRole', { 'accountId', 'identifier', 'role' })
ForwardAction('tiltann_banking:ui:business:removeMember', 'tiltann_banking:society:removeMember', { 'accountId', 'identifier' })
ForwardAction('tiltann_banking:ui:business:setMemberCardLimit', 'tiltann_banking:society:setMemberCardLimit', { 'accountId', 'identifier', 'limit' })
ForwardResult('tiltann_banking:ui:business:listGradeRoles', 'tiltann_banking:society:listGradeRoles', { 'accountId' })
ForwardAction('tiltann_banking:ui:business:setGradeRole', 'tiltann_banking:society:setGradeRole', { 'accountId', 'grade', 'role' })
