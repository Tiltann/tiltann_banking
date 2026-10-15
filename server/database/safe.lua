--- @module server.database.safe
--- Every oxmysql call in this resource goes through SafeQuery instead of
--- being pcall-wrapped individually at 40+ call sites. This is the single
--- place that pattern is written, so a future contributor can't forget it.
--- A failed query is logged with the statement and its parameters; in
--- debug mode every query is logged with its duration.

TbDb = {}

--- The first line of a (possibly multi-line) SQL statement, whitespace
--- collapsed, enough to recognise the query in a log without the noise.
---@param query any
---@return string
local function Describe(query)
	if type(query) ~= 'string' then
		return tostring(query)
	end

	local collapsed = query:gsub('%s+', ' '):gsub('^ ', '')

	if #collapsed > 160 then
		collapsed = collapsed:sub(1, 160) .. '…'
	end

	return collapsed
end

--- Runs an oxmysql `.await`-style function and never throws, callers get
--- `ok, result` back instead of a Lua error propagating out of a money flow.
---@generic T
---@param fn fun(...): T The oxmysql function to call, e.g. MySQL.query.await.
---@param query string
---@param params table?
---@return boolean ok
---@return T|string resultOrError On failure, the second value is the error message.
function TbDb.SafeQuery(fn, query, params)
	local started = GetGameTimer()
	local ok, result = pcall(fn, query, params)

	if not ok then
		TbLogger.Error('db', 'query failed', { query = Describe(query), params = params, error = result })
		return false, result
	end

	if TbLogger.IsDebug() then
		local rows = type(result) == 'table' and #result or result
		TbLogger.Debug('db', Describe(query), { params = params, ms = GetGameTimer() - started, result = rows })
	end

	return true, result
end

--- Convenience wrapper for a SELECT expected to return zero-or-one row.
---@param query string
---@param params table?
---@return boolean ok
---@return table? row
function TbDb.SelectOne(query, params)
	local ok, rows = TbDb.SafeQuery(MySQL.query.await, query, params)

	if not ok then
		return false, nil
	end

	return true, rows and rows[1] or nil
end

--- Convenience wrapper for a SELECT expected to return many rows.
---@param query string
---@param params table?
---@return boolean ok
---@return table rows Empty table (never nil) on both success-with-no-rows and failure.
function TbDb.SelectMany(query, params)
	local ok, rows = TbDb.SafeQuery(MySQL.query.await, query, params)

	if not ok or not rows then
		return ok, {}
	end

	return true, rows
end

--- Convenience wrapper for an INSERT, returning the new row's id.
---@param query string
---@param params table?
---@return boolean ok
---@return integer? insertId
function TbDb.Insert(query, params)
	local ok, insertId = TbDb.SafeQuery(MySQL.insert.await, query, params)

	if not ok then
		return false, nil
	end

	return true, insertId
end

--- Convenience wrapper for an UPDATE/DELETE, returning affected row count.
---@param query string
---@param params table?
---@return boolean ok
---@return integer affectedRows 0 on failure, never nil.
function TbDb.Update(query, params)
	local ok, affected = TbDb.SafeQuery(MySQL.update.await, query, params)

	if not ok then
		return false, 0
	end

	return true, affected or 0
end
