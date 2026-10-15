--- @module server.standing_orders.standing_orders
--- Recurring transfers (rent, salaries) from an account the creator
--- controls to any account number. The tick runs due orders through
--- TbAccounts.Transfer; an order that can't be funded counts a failed run
--- and is deactivated after Config.StandingOrders.MaxFailedRuns. A true
--- no-op when disabled, nothing can be created and the tick never starts.

TbStandingOrders = {}

--- Whether the caller may create/cancel orders on `accountId`: their own
--- personal account (savings only if allowed), or a business role with
--- `withdraw`.
---@param source integer
---@param accountId integer
---@return TbAccount? account
---@return string? errorReason
local function GetControlledAccount(source, accountId)
	local identifier = TbFramework.GetIdentifier(source)
	local account = identifier and TbAccounts.GetById(accountId)

	if not account then
		return nil, 'account_not_found'
	end

	if account.type == TbEnums.AccountType.SOCIETY then
		if not TbSocietyPermissions.GetCapabilities(source, accountId).withdraw then
			return nil, 'society_no_permission'
		end

		return account, nil
	end

	if account.ownerIdentifier ~= identifier then
		return nil, 'account_not_found'
	end

	if account.type == TbEnums.AccountType.SAVINGS and not Config.StandingOrders.AllowFromSavings then
		return nil, 'order_savings_not_allowed'
	end

	return account, nil
end

---@param row table
---@return TbStandingOrder
local function RowToOrder(row)
	local to = TbAccounts.GetByNumber(row.to_account_number)

	return {
		id = row.id,
		fromAccountId = row.from_account_id,
		toAccountNumber = row.to_account_number,
		toName = to and to.name or nil,
		amount = row.amount,
		intervalSeconds = row.interval_seconds,
		nextRunAt = row.next_run_at,
		note = row.note,
		active = TbUtils.ToBool(row.active),
		failedRuns = row.failed_runs,
	}
end

---@param accountId integer
---@return TbStandingOrder[]
function TbStandingOrders.ListForAccount(accountId)
	local ok, rows = TbDb.SelectMany('SELECT * FROM tb_standing_orders WHERE from_account_id = ? ORDER BY active DESC, next_run_at ASC', { accountId })

	if not ok then
		return {}
	end

	local orders = {}

	for i, row in ipairs(rows) do
		orders[i] = RowToOrder(row)
	end

	return orders
end

---@param accountIds integer[]
---@return TbStandingOrder[]
function TbStandingOrders.ListAcross(accountIds)
	local all = {}

	for _, accountId in ipairs(accountIds) do
		for _, order in ipairs(TbStandingOrders.ListForAccount(accountId)) do
			all[#all + 1] = order
		end
	end

	return all
end

---@param source integer
---@param fromAccountId integer
---@param toNumber string
---@param amount integer
---@param intervalSeconds integer
---@param note string?
---@return boolean ok
---@return string? errorReason
function TbStandingOrders.Create(source, fromAccountId, toNumber, amount, intervalSeconds, note)
	if not Config.StandingOrders.Enabled then
		return false, 'order_disabled'
	end

	local account, reason = GetControlledAccount(source, fromAccountId)

	if not account then
		return false, reason
	end

	amount = TbUtils.RoundMoney(amount)
	intervalSeconds = math.min(TbUtils.RoundMoney(intervalSeconds), 315360000)

	if amount < Config.Limits.MinTransactionAmount or amount > Config.Limits.MaxTransactionAmount then
		return false, 'tx_limit_exceeded'
	end

	if intervalSeconds < Config.StandingOrders.MinIntervalSeconds then
		return false, 'order_interval_too_short'
	end

	-- a server id works too, the order then runs against that player's main account
	local recipient = TbAccounts.ResolveRecipient(toNumber)

	if not recipient then
		return false, 'tx_recipient_not_found'
	end

	if recipient.id == account.id then
		return false, 'tx_same_account'
	end

	local ok, countRow = TbDb.SelectOne('SELECT COUNT(*) AS count FROM tb_standing_orders WHERE from_account_id = ? AND active = 1', { account.id })

	if ok and countRow and countRow.count >= Config.StandingOrders.MaxPerAccount then
		return false, 'order_limit_reached'
	end

	local nextRun = os.date('!%Y-%m-%d %H:%M:%S', os.time() + intervalSeconds)
	local insertOk = TbDb.Insert(
		[[INSERT INTO tb_standing_orders (from_account_id, to_account_number, amount, interval_seconds, next_run_at, note, created_by)
			VALUES (?, ?, ?, ?, ?, ?, ?)]],
		{ account.id, recipient.number, amount, intervalSeconds, nextRun, TbUtils.CleanName(note, 100), TbFramework.GetIdentifier(source) }
	)

	return insertOk == true, insertOk and nil or 'order_limit_reached'
end

---@param source integer
---@param orderId integer
---@return boolean ok
---@return string? errorReason
function TbStandingOrders.Cancel(source, orderId)
	local ok, row = TbDb.SelectOne('SELECT * FROM tb_standing_orders WHERE id = ?', { orderId })

	if not ok or not row then
		return false, 'order_not_found'
	end

	local account, reason = GetControlledAccount(source, row.from_account_id)

	if not account then
		return false, reason
	end

	return TbDb.Update('DELETE FROM tb_standing_orders WHERE id = ?', { orderId }), nil
end

--- Runs one due order. Boxed on its own so one bad row cannot stop the rest.
---@param row table
local function RunOrder(row)
	-- Bump next_run_at first so an overlapping tick can't run it twice.
	local claimOk, claimed = TbDb.Update(
		'UPDATE tb_standing_orders SET next_run_at = DATE_ADD(NOW(), INTERVAL ? SECOND) WHERE id = ? AND next_run_at <= NOW()',
		{ row.interval_seconds, row.id }
	)

	if claimOk and claimed > 0 then
		local recipient = TbAccounts.GetByNumber(row.to_account_number)
		local transferred = recipient ~= nil and TbAccounts.Transfer(
			row.from_account_id, recipient.id, row.amount, TbEnums.TransactionType.STANDING_ORDER,
			row.created_by, row.note or 'Standing order', { standingOrderId = row.id }
		)

		if transferred then
			if row.failed_runs > 0 then
				TbDb.Update('UPDATE tb_standing_orders SET failed_runs = 0 WHERE id = ?', { row.id })
			end
		else
			local failed = row.failed_runs + 1
			local deactivate = failed >= Config.StandingOrders.MaxFailedRuns or recipient == nil

			TbDb.Update('UPDATE tb_standing_orders SET failed_runs = ?, active = ? WHERE id = ?', { failed, deactivate and 0 or 1, row.id })

			if TbLog then
				TbLog('transfers', deactivate and 'Standing order deactivated' or 'Standing order failed', {
					{ name = 'Order', value = tostring(row.id) },
					{ name = 'From account', value = tostring(row.from_account_id) },
					{ name = 'Amount', value = tostring(row.amount) },
					{ name = 'Failed runs', value = tostring(failed) },
				}, Config.Logs.Colors.warning)
			end
		end
	end
end

--- One pass over due, active orders.
local function RunTick()
	local ok, rows = TbDb.SelectMany('SELECT * FROM tb_standing_orders WHERE active = 1 AND next_run_at <= NOW()')

	if not ok then
		return
	end

	for _, row in ipairs(rows) do
		TbSafe.Run('orders:run', RunOrder, row)
	end
end

local tickStarted = false

function TbStandingOrders.StartTick()
	if tickStarted or not Config.StandingOrders.Enabled then
		return
	end

	tickStarted = true

	CreateThread(function()
		while true do
			Wait(Config.StandingOrders.CheckIntervalMs)
			TbSafe.Run('orders:tick', RunTick)
		end
	end)
end

TbSafe.Callback('tiltann_banking:orders:list', function(source, accountId)
	local account = GetControlledAccount(source, tonumber(accountId) or 0)
	return account and TbStandingOrders.ListForAccount(account.id) or {}
end)

TbSafe.Callback('tiltann_banking:orders:create', function(source, fromAccountId, toNumber, amount, intervalSeconds, note)
	return TbStandingOrders.Create(source, tonumber(fromAccountId) or 0, tostring(toNumber or ''), tonumber(amount) or 0, tonumber(intervalSeconds) or 0, note)
end)

TbSafe.Callback('tiltann_banking:orders:cancel', function(source, orderId)
	return TbStandingOrders.Cancel(source, tonumber(orderId) or 0)
end)
