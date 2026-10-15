--- @module server.bridge.external_bridge
--- Keeps tb_accounts (this resource's authoritative balance table) in sync
--- with the places other resources may still read or write directly: the
--- framework's own bank balance for a player's default personal account, and
--- the framework's society accounts for a business linked to a job. Extra
--- personal accounts, savings accounts and standalone businesses are never
--- mirrored. What those places are lives in shared/framework/.
---
--- Outbound (us to them) is a plain push after every balance change. A
--- failure never rolls back the local change, the mirror is just stale until
--- the next push or the inbound poll fixes it.
---
--- Inbound (them to us) can only be polled, FiveM can't intercept another
--- resource writing to its own account. tb_sync_log's outbound rows let the
--- poll tell "we pushed this" apart from "something else changed it".

TbExternalBridge = {}

local societyTargets = {}

--- Asks the framework which society systems are running. Called once from
--- server/main.lua after all resources have started.
function TbExternalBridge.DetectSocietyTargets()
	societyTargets = Config.Bridge.ForceDisabled.society and {} or TbFramework.GetSocietyTargets()
end

---@param accountId integer
---@param target string
---@param direction 'outbound'|'inbound'
---@param resultingBalance integer
local function LogSync(accountId, target, direction, resultingBalance)
	TbDb.Insert(
		'INSERT INTO tb_sync_log (account_id, target, direction, resulting_balance) VALUES (?, ?, ?, ?)',
		{ accountId, target, direction, resultingBalance }
	)
end

--- Pushes a default personal account's balance into the framework's bank.
---@param account TbAccount
local function PushToBank(account)
	local source = TbFramework.GetSourceByIdentifier(account.ownerIdentifier)
	local ok

	if source then
		ok = TbFramework.SetBank(source, account.balance)
	else
		ok = TbFramework.SetBankOffline(account.ownerIdentifier, account.balance)
	end

	if ok then
		LogSync(account.id, TbFramework.BankTarget, 'outbound', account.balance)
		TbLogger.Debug('bridge', 'pushed balance to framework bank', { account = account.number, balance = account.balance })
	else
		TbLogger.Warn('bridge', 'framework bank push failed, it stays out of sync until the next push', { account = account.number })
	end
end

--- Pushes a job business balance into every running society system.
---@param account TbAccount
local function PushToSociety(account)
	for _, target in ipairs(societyTargets) do
		local ok, err = pcall(target.set, account.jobName, account.balance)

		if ok then
			LogSync(account.id, target.name, 'outbound', account.balance)
			TbLogger.Debug('bridge', 'pushed balance to ' .. target.name, { job = account.jobName, balance = account.balance })
		else
			TbLogger.Warn('bridge', target.name .. ' push failed', { job = account.jobName, error = err })
		end
	end
end

--- Public entry point called after every balance mutation. Decides whether
--- the account has an external mirror at all, and which.
---@param account TbAccount
function TbExternalBridge.PushBalance(account)
	if account.type == TbEnums.AccountType.PERSONAL and account.ownerIdentifier then
		local owner = TbFramework.GetSourceByIdentifier(account.ownerIdentifier)

		if owner then
			TriggerClientEvent('tiltann_banking:refresh', owner)
		end
	end

	if account.type == TbEnums.AccountType.PERSONAL and account.isDefault then
		if not Config.Bridge.ForceDisabled.player then
			TbSafe.Run('bridge:pushBank', PushToBank, account)
		end
	elseif account.type == TbEnums.AccountType.SOCIETY and account.jobName then
		if not Config.Bridge.ForceDisabled.society then
			TbSafe.Run('bridge:pushSociety', PushToSociety, account)
		end
	end
end

---@param accountId integer
---@param target string
---@return integer? lastPushedBalance
local function GetLastOutboundBalance(accountId, target)
	local ok, row = TbDb.SelectOne(
		[[SELECT resulting_balance FROM tb_sync_log
			WHERE account_id = ? AND target = ? AND direction = 'outbound'
			ORDER BY id DESC LIMIT 1]],
		{ accountId, target }
	)

	if not ok or not row then
		return nil
	end

	return row.resulting_balance
end

--- Applies an externally-detected change to our own row, recorded as a
--- `sync_correction` so the audit trail shows where the money came from.
---@param account TbAccount
---@param target string
---@param newExternalBalance integer
local function ApplyInboundChange(account, target, newExternalBalance)
	newExternalBalance = TbUtils.RoundMoney(newExternalBalance)

	local delta = newExternalBalance - account.balance

	if delta == 0 or newExternalBalance < 0 then
		return
	end

	local updated = TbDb.Update('UPDATE tb_accounts SET balance = ? WHERE id = ?', { newExternalBalance, account.id })

	if not updated then
		TbLogger.Error('bridge', 'inbound balance change could not be applied', { account = account.number, balance = newExternalBalance })
		return
	end

	-- A big jump is most likely an admin setting the balance, so the old
	-- history means nothing anymore: wipe it and start over with one entry.
	if Config.Bridge.ExternalChange == 'clear' and math.abs(delta) >= Config.Bridge.ClearThreshold then
		TbDb.Update('DELETE FROM tb_transactions WHERE from_account_id = ? OR to_account_id = ?', { account.id, account.id })

		TbDb.Insert(
			'INSERT INTO tb_transactions (to_account_id, type, amount, balance_after, note, metadata) VALUES (?, ?, ?, ?, ?, ?)',
			{
				account.id, TbEnums.TransactionType.SYNC_CORRECTION, newExternalBalance, newExternalBalance,
				('Balance reset to %d outside the bank'):format(newExternalBalance), json.encode({ target = target, reset = true }),
			}
		)

		LogSync(account.id, target, 'inbound', newExternalBalance)
		return
	end

	-- amounts are stored positive, the side says if it was added or removed
	local column = delta > 0 and 'to_account_id' or 'from_account_id'

	TbDb.Insert(
		('INSERT INTO tb_transactions (%s, type, amount, balance_after, note, metadata) VALUES (?, ?, ?, ?, ?, ?)'):format(column),
		{
			account.id, TbEnums.TransactionType.SYNC_CORRECTION, math.abs(delta), newExternalBalance,
			target == TbFramework.BankTarget and 'Balance changed outside the bank' or 'Company balance changed outside the bank', json.encode({ target = target }),
		}
	)

	LogSync(account.id, target, 'inbound', newExternalBalance)

	if TbLog then
		TbLog('society_sync', 'External balance change synced', {
			{ name = 'Account', value = account.number },
			{ name = 'Target', value = target },
			{ name = 'Delta', value = tostring(delta) },
		})
	end
end

--- Compares one online player's framework bank balance with their default
--- account and books the difference. Returns true when something changed.
---@param player { source: integer, identifier: string }
---@return boolean changed
local function SyncPlayerBank(player)
	local account = TbAccounts.GetDefaultForPlayer(player.identifier)
	local balance = account and TbFramework.GetBank(player.source)

	if type(balance) ~= 'number' or GetLastOutboundBalance(account.id, TbFramework.BankTarget) == balance then
		return false
	end

	ApplyInboundChange(account, TbFramework.BankTarget, balance)
	return true
end

--- Polls the framework bank for every online player's default account.
--- Online only: an offline player's balance only changes through a raw DB
--- write, which is rare enough to catch on the next login.
local function PollBank()
	if Config.Bridge.ForceDisabled.player then
		return
	end

	for _, player in ipairs(TbFramework.GetPlayers()) do
		-- Per player, so one broken record cannot skip everyone after it.
		local ok, changed = TbSafe.Run('bridge:syncPlayer', SyncPlayerBank, player)

		if ok and changed then
			TriggerClientEvent('tiltann_banking:refresh', player.source)
		end
	end
end

-- The client reports that its framework bank balance changed. Only used as a
-- trigger, the value is read again on the server. One sync per second at most.
local lastSync = {}

RegisterNetEvent('tiltann_banking:bankChanged', function()
	local source = source
	local now = GetGameTimer()

	if type(source) ~= 'number' or source <= 0 then
		return
	end

	if Config.Bridge.ForceDisabled.player or (lastSync[source] and now - lastSync[source] < 1000) then
		return
	end

	lastSync[source] = now

	TbSafe.Run('bridge:bankChanged', function()
		local identifier = TbFramework.GetIdentifier(source)

		if identifier then
			SyncPlayerBank({ source = source, identifier = identifier })
			TriggerClientEvent('tiltann_banking:refresh', source)
		end
	end)
end)

AddEventHandler('playerDropped', function()
	lastSync[source] = nil
end)

--- Polls every society system that can be read, same diff logic.
local function PollSociety()
	local pollable = {}

	for _, target in ipairs(societyTargets) do
		if target.get then
			pollable[#pollable + 1] = target
		end
	end

	if #pollable == 0 then
		return
	end

	local ok, rows = TbDb.SelectMany("SELECT * FROM tb_accounts WHERE type = 'society' AND job_name IS NOT NULL AND deleted_at IS NULL")

	if not ok then
		return
	end

	for _, row in ipairs(rows) do
		local account = TbAccounts.RowToAccount(row)

		for _, target in ipairs(pollable) do
			local readOk, balance = pcall(target.get, account.jobName)

			if readOk and type(balance) == 'number' and GetLastOutboundBalance(account.id, target.name) ~= balance then
				TbSafe.Run('bridge:applySociety', ApplyInboundChange, account, target.name, balance)
			elseif not readOk then
				TbLogger.Warn('bridge', target.name .. ' read failed', { job = account.jobName, error = balance })
			end
		end
	end
end

local pollThreadStarted = false

--- Starts the recurring poll thread, only the first call does anything.
function TbExternalBridge.StartPolling()
	if pollThreadStarted then
		return
	end

	pollThreadStarted = true

	CreateThread(function()
		while true do
			Wait(Config.Bridge.PollIntervalMs)
			TbSafe.Run('bridge:pollBank', PollBank)
			TbSafe.Run('bridge:pollSociety', PollSociety)
		end
	end)
end
