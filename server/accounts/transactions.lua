--- @module server.accounts.transactions
--- Read-side queries against tb_transactions: filtered statements, the
--- grouped aggregation behind the business payout graph, and the 7-day
--- in/out summary behind the personal dashboard's week graph. One place
--- knows this table's shape, every UI query builds on these.

TbTransactions = {}

---@class TbTransactionFilters
---@field type TbTransactionType?
---@field minAmount integer?
---@field maxAmount integer?
---@field from string? 'YYYY-MM-DD' inclusive
---@field to string? 'YYYY-MM-DD' inclusive

--- Converts a raw oxmysql row into the camelCase TbTransaction shape.
---@param row table
---@return TbTransaction
function TbTransactions.RowToTransaction(row)
	local metadata = nil

	if row.metadata then
		local ok, decoded = pcall(json.decode, row.metadata)
		metadata = ok and decoded or nil
	end

	return {
		id = row.id,
		fromAccountId = row.from_account_id,
		toAccountId = row.to_account_id,
		type = row.type,
		amount = row.amount,
		balanceAfter = row.balance_after,
		actorIdentifier = row.actor_identifier,
		note = row.note,
		metadata = metadata,
		createdAt = row.created_at,
	}
end

--- Appends the optional filter clauses. Every value is a bound parameter,
--- nothing player-typed is ever interpolated into the query string.
---@param filters TbTransactionFilters?
---@param clauses string[]
---@param params any[]
local function ApplyFilters(filters, clauses, params)
	if type(filters) ~= 'table' then
		return
	end

	if type(filters.type) == 'string' and TbEnums.TransactionType[string.upper(filters.type)] then
		clauses[#clauses + 1] = 'type = ?'
		params[#params + 1] = filters.type
	end

	if tonumber(filters.minAmount) then
		clauses[#clauses + 1] = 'amount >= ?'
		params[#params + 1] = tonumber(filters.minAmount)
	end

	if tonumber(filters.maxAmount) then
		clauses[#clauses + 1] = 'amount <= ?'
		params[#params + 1] = tonumber(filters.maxAmount)
	end

	if type(filters.from) == 'string' and filters.from:match('^%d%d%d%d%-%d%d%-%d%d$') then
		clauses[#clauses + 1] = 'created_at >= ?'
		params[#params + 1] = filters.from .. ' 00:00:00'
	end

	if type(filters.to) == 'string' and filters.to:match('^%d%d%d%d%-%d%d%-%d%d$') then
		clauses[#clauses + 1] = 'created_at <= ?'
		params[#params + 1] = filters.to .. ' 23:59:59'
	end
end

--- Clause that hides what the account's owner cleared. The cutoff is read
--- in SQL from tb_accounts so no clock or format conversion is involved.
local CLEARED_SINGLE = 'created_at > COALESCE((SELECT history_cleared_at FROM tb_accounts WHERE id = ?), \'1000-01-01 00:00:00\')'

--- Soft clear: remembers "now" as the cutoff for this account's statement.
--- tb_transactions is never touched, the daily withdraw limit and the audit
--- trail keep reading every row, and a transfer stays visible to the other side.
---@param accountId integer
---@return boolean ok
function TbTransactions.ClearHistory(accountId)
	local ok, affected = TbDb.Update('UPDATE tb_accounts SET history_cleared_at = NOW() WHERE id = ? AND deleted_at IS NULL', { accountId })
	return ok and affected > 0
end

--- A page of one account's statement, most recent first.
---@param accountId integer
---@param limit integer?
---@param offset integer?
---@param filters TbTransactionFilters?
---@return TbTransaction[]
function TbTransactions.GetForAccount(accountId, limit, offset, filters)
	local clauses = { '(from_account_id = ? OR to_account_id = ?)', CLEARED_SINGLE }
	local params = { accountId, accountId, accountId }

	ApplyFilters(filters, clauses, params)

	params[#params + 1] = math.max(1, math.min(TbUtils.RoundMoney(limit or 25), 200))
	params[#params + 1] = math.max(0, TbUtils.RoundMoney(offset or 0))

	local ok, rows = TbDb.SelectMany(
		('SELECT * FROM tb_transactions WHERE %s ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?'):format(table.concat(clauses, ' AND ')),
		params
	)

	if not ok then
		return {}
	end

	local transactions = {}

	for i, row in ipairs(rows) do
		transactions[i] = TbTransactions.RowToTransaction(row)
	end

	return transactions
end

--- The most recent rows across several accounts (a player's whole set) for
--- the dashboard's "latest transactions" list.
---@param accountIds integer[]
---@param limit integer?
---@return TbTransaction[]
function TbTransactions.GetLatestAcross(accountIds, limit)
	if #accountIds == 0 then
		return {}
	end

	local placeholders = {}
	local params = {}

	for i, id in ipairs(accountIds) do
		placeholders[i] = '?'
		params[#params + 1] = id
	end

	for _, id in ipairs(accountIds) do
		params[#params + 1] = id
	end

	-- A row counts when it touches one of the accounts and is newer than
	-- that account's own cleared cutoff.
	for _, id in ipairs(accountIds) do
		params[#params + 1] = id
	end

	params[#params + 1] = limit or 5

	local list = table.concat(placeholders, ',')
	local ok, rows = TbDb.SelectMany(
		([[SELECT t.* FROM tb_transactions t
		WHERE (t.from_account_id IN (%s) OR t.to_account_id IN (%s))
		AND EXISTS (
			SELECT 1 FROM tb_accounts a
			WHERE a.id IN (%s) AND (a.id = t.from_account_id OR a.id = t.to_account_id)
			AND (a.history_cleared_at IS NULL OR t.created_at > a.history_cleared_at)
		)
		ORDER BY t.created_at DESC, t.id DESC LIMIT ?]]):format(list, list, list),
		params
	)

	if not ok then
		return {}
	end

	local transactions = {}

	for i, row in ipairs(rows) do
		transactions[i] = TbTransactions.RowToTransaction(row)
	end

	return transactions
end

---@class TbDailyTotals
---@field day string 'YYYY-MM-DD'
---@field deposits integer
---@field withdrawals integer
---@field adminAdjustments integer

--- Daily totals for the business payout graph. Includes admin_adjustment so
--- a staff balance reset shows up honestly instead of vanishing. Transfers
--- between two tb_accounts net out and are intentionally excluded here.
---@param accountId integer
---@param sinceIso string
---@return TbDailyTotals[]
function TbTransactions.GetGroupedTotals(accountId, sinceIso)
	local ok, rows = TbDb.SelectMany(
		[[SELECT
			DATE(created_at) AS day,
			SUM(CASE WHEN type = 'deposit' THEN amount ELSE 0 END) AS deposits,
			SUM(CASE WHEN type = 'withdraw' THEN amount ELSE 0 END) AS withdrawals,
			SUM(CASE WHEN type = 'admin_adjustment' THEN amount ELSE 0 END) AS admin_adjustments
		FROM tb_transactions
		WHERE created_at >= ? AND (from_account_id = ? OR to_account_id = ?) AND ]] .. CLEARED_SINGLE .. [[

		GROUP BY DATE(created_at) ORDER BY day ASC]],
		{ sinceIso, accountId, accountId, accountId }
	)

	if not ok then
		return {}
	end

	local days = {}

	for i, row in ipairs(rows) do
		days[i] = {
			day = row.day,
			deposits = row.deposits or 0,
			withdrawals = row.withdrawals or 0,
			adminAdjustments = row.admin_adjustments or 0,
		}
	end

	return days
end

---@class TbWeekPoint
---@field day string 'YYYY-MM-DD'
---@field income integer Money that arrived in any of the accounts.
---@field expenses integer Money that left any of the accounts.

--- Last-7-days income vs expenses across a player's accounts, for the
--- personal dashboard's week graph (the pefcl "Summary"). Money moved
--- between two of the SAME player's accounts is skipped so it doesn't show
--- as both income and expense.
---@param accountIds integer[]
---@return TbWeekPoint[]
function TbTransactions.GetWeekSummary(accountIds)
	if #accountIds == 0 then
		return {}
	end

	local placeholders = {}
	local params = {}

	for i in ipairs(accountIds) do
		placeholders[i] = '?'
	end

	local list = table.concat(placeholders, ',')

	-- The IN list appears five times in the query, bind it five times.
	for _ = 1, 5 do
		for _, id in ipairs(accountIds) do
			params[#params + 1] = id
		end
	end

	local ok, rows = TbDb.SelectMany(
		([[SELECT
			DATE(created_at) AS day,
			SUM(CASE WHEN to_account_id IN (%s) AND (from_account_id IS NULL OR from_account_id NOT IN (%s)) THEN amount ELSE 0 END) AS income,
			SUM(CASE WHEN from_account_id IN (%s) AND (to_account_id IS NULL OR to_account_id NOT IN (%s)) THEN amount ELSE 0 END) AS expenses
		FROM tb_transactions t
		WHERE created_at >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)
		AND EXISTS (
			SELECT 1 FROM tb_accounts a
			WHERE a.id IN (%s) AND (a.id = t.from_account_id OR a.id = t.to_account_id)
			AND (a.history_cleared_at IS NULL OR t.created_at > a.history_cleared_at)
		)
		GROUP BY DATE(created_at) ORDER BY day ASC]]):format(list, list, list, list, list),
		params
	)

	if not ok then
		return {}
	end

	local points = {}

	for i, row in ipairs(rows) do
		points[i] = { day = row.day, income = row.income or 0, expenses = row.expenses or 0 }
	end

	return points
end

--- Sum of today's withdrawals a player made from a set of accounts, the
--- daily limit check for personal ATM use and company cards.
---@param identifier string
---@param accountIds integer[]
---@return integer
function TbTransactions.GetTodaysWithdrawals(identifier, accountIds)
	if #accountIds == 0 then
		return 0
	end

	local placeholders = {}
	local params = { identifier }

	for i, id in ipairs(accountIds) do
		placeholders[i] = '?'
		params[#params + 1] = id
	end

	local ok, row = TbDb.SelectOne(
		([[SELECT COALESCE(SUM(amount), 0) AS total FROM tb_transactions
			WHERE type = 'withdraw' AND actor_identifier = ? AND from_account_id IN (%s) AND created_at >= CURDATE()]]):format(table.concat(placeholders, ',')),
		params
	)

	if not ok or not row then
		return 0
	end

	return row.total or 0
end
