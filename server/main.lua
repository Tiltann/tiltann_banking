--- @module server.main
--- Wires the resource together: starts every background tick (each
--- self-guards on its own Config.*.Enabled) and registers the admin
--- commands. Balance overrides ALWAYS write an `admin_adjustment`
--- transaction, that's what lets the business payout graph show "what was
--- given out on a reset" at all, so there is deliberately no other path.
--- Every command runs inside TbSafe.Command's error boundary.

--- Sets an account's balance to an exact value as an admin adjustment.
---@param account TbAccount
---@param newBalance integer
---@param adminIdentifier string
---@return boolean ok
local function AdminSetBalance(account, newBalance, adminIdentifier)
	local delta = newBalance - account.balance
	local note = ('Balance set to %d by admin'):format(newBalance)

	-- A set starts the account over, the old history no longer adds up.
	local cleared = TbDb.Update('DELETE FROM tb_transactions WHERE from_account_id = ? OR to_account_id = ?', { account.id, account.id })

	if not cleared then
		TbLogger.Error('command', 'could not clear the old history before the balance set', { account = account.id })
	end

	local moved = true

	if delta > 0 then
		moved = TbAccounts.Credit(account.id, delta, TbEnums.TransactionType.ADMIN_ADJUSTMENT, adminIdentifier, note)
	elseif delta < 0 then
		moved = TbAccounts.Debit(account.id, -delta, TbEnums.TransactionType.ADMIN_ADJUSTMENT, adminIdentifier, note)
	end

	if not moved then
		TbLogger.Error('command', 'balance set failed', { account = account.id, balance = newBalance })
		return false
	end

	if TbLog then
		TbLog('admin_actions', 'Balance adjusted', {
			{ name = 'Admin', value = adminIdentifier },
			{ name = 'Account', value = account.number },
			{ name = 'New balance', value = tostring(newBalance) },
		}, Config.Logs.Colors.warning)
	end

	return true
end

---@param source integer
---@param message string
local function Reply(source, message)
	if source == 0 then
		print(('[tiltann_banking] %s'):format(message))
	else
		TriggerClientEvent('ox_lib:notify', source, { description = message })
	end
end

---@param source integer
---@return boolean
local function IsAdmin(source)
	if TbAdmin.Is(source) then
		return true
	end

	TbLogger.Warn('command', 'refused, not an admin', { source = source }, source)
	Reply(source, 'tiltann_banking: you are not an admin (Config.Admin.Group or the tiltann_banking.admin ace)')
	return false
end


--- /tb_setbalance [player id] [amount], the target's default account.
TbSafe.Command('tb_setbalance', function(source, args)
	if not IsAdmin(source) then
		return
	end

	local adminIdentifier = source ~= 0 and TbFramework.GetIdentifier(source) or nil
	local targetIdentifier = TbFramework.GetIdentifier(tonumber(args[1]) or -1)
	local newBalance = tonumber(args[2])

	if not targetIdentifier or not newBalance or newBalance ~= newBalance or newBalance < 0 or newBalance > 2 ^ 53 then
		Reply(source, 'Usage: /tb_setbalance [id] [amount]')
		return
	end

	local account = TbAccounts.GetOrCreateDefault(targetIdentifier)

	if account then
		if AdminSetBalance(account, math.floor(newBalance), adminIdentifier or 'console') then
			Reply(source, ('Balance of %s set to %d'):format(account.number, math.floor(newBalance)))
		else
			Reply(source, 'Balance could not be set, see the server console')
		end
	end
end, false)

--- /tb_setsociety [job] [amount], a job-linked business.
TbSafe.Command('tb_setsociety', function(source, args)
	if not IsAdmin(source) then
		return
	end

	local adminIdentifier = source ~= 0 and TbFramework.GetIdentifier(source) or nil
	local newBalance = tonumber(args[2])

	if not args[1] or not newBalance or newBalance ~= newBalance or newBalance < 0 or newBalance > 2 ^ 53 then
		Reply(source, 'Usage: /tb_setsociety [job] [amount]')
		return
	end

	local account = TbAccounts.GetOrCreateJobAccount(args[1])

	if account then
		if AdminSetBalance(account, math.floor(newBalance), adminIdentifier or 'console') then
			Reply(source, ('Balance of %s set to %d'):format(account.name, math.floor(newBalance)))
		else
			Reply(source, 'Balance could not be set, see the server console')
		end
	end
end, false)

--- /tb_setgraderole [job] [grade] [owner|admin|contributor]
TbSafe.Command('tb_setgraderole', function(source, args)
	if not IsAdmin(source) then
		return
	end

	local grade = tonumber(args[2])

	if not args[1] or not grade or not TbSocietyPermissions.SetJobRole(args[1], math.floor(grade), args[3]) then
		Reply(source, 'Usage: /tb_setgraderole [job] [grade] [owner|admin|contributor]')
	end
end, false)

--- /tb_debug [on|off], toggles Config.Logs.Debug at runtime (console or admin).
TbSafe.Command('tb_debug', function(source, args)
	if not IsAdmin(source) then
		return
	end

	local enabled

	if args[1] == 'on' then
		enabled = true
	elseif args[1] == 'off' then
		enabled = false
	else
		enabled = not TbLogger.IsDebug()
	end

	TbLogger.SetDebug(enabled)
	TbLogger.Info('command', ('debug logging %s'):format(enabled and 'enabled' or 'disabled'), { by = source })

	-- the clients have their own switch (NUI and UI lines show in F8)
	TriggerClientEvent('tiltann_banking:setDebug', -1, enabled)
	Reply(source, ('tiltann_banking debug logging %s (server console and F8)'):format(enabled and 'ON' or 'OFF'))
end, false)

-- A client that starts after debug was switched on asks for the current state.
RegisterNetEvent('tiltann_banking:requestDebug', function()
	TriggerClientEvent('tiltann_banking:setDebug', source, TbLogger.IsDebug())
end)

-- Startup wiring. The update check needs no database, so it runs straight
-- away, an owner whose schema is broken should still learn that a fix has
-- been released. Everything that reads or writes money waits for
-- server/database/migrate.lua to confirm the schema (MySQL.ready, then an
-- install if tables are missing), so no tick ever queries a table that does
-- not exist yet.
CreateThread(function()
	Wait(0)
	TbSafe.Run('startup:updater', TbUpdater.Start)
end)

TbMigrate.OnReady(function()
	local started = GetGameTimer()

	for _, step in ipairs({
		{ 'bridge:detect', TbExternalBridge.DetectSocietyTargets },
		{ 'bridge:polling', TbExternalBridge.StartPolling },
		{ 'savings:interest', TbSavings.StartInterestTick },
		{ 'loans:repayment', TbLoans.StartRepaymentTick },
		{ 'tax:periodic', TbTax.StartPeriodicTick },
		{ 'billing:overdue', TbBilling.StartOverdueSweep },
		{ 'orders:tick', TbStandingOrders.StartTick },
	}) do
		local ok = TbSafe.Run(('startup:%s'):format(step[1]), step[2])

		if not ok then
			TbLogger.Error('startup', ('%s did not start, the feature is unavailable until the resource is restarted'):format(step[1]))
		end
	end

	TbLogger.Info('startup', 'ready', {
		version = GetResourceMetadata(GetCurrentResourceName(), 'version', 0),
		ms = GetGameTimer() - started,
		debug = TbLogger.IsDebug(),
		ox_logger = Config.Logs.OxLogger and Config.Logs.OxLogger.Enabled or false,
		savings = Config.Savings.Enabled, loans = Config.Loans.Enabled, tax = Config.Tax.Enabled,
		billing = Config.Billing.Enabled, cards = Config.Cards.Enabled, orders = Config.StandingOrders.Enabled,
	})
end)
