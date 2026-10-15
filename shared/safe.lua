--- @module shared.safe
--- Error boundaries for every entry point into the resource: server
--- callbacks, admin commands, background ticks, NUI callbacks. Each wrapper
--- runs the handler under xpcall with a traceback, logs the failure through
--- TbLogger with what was being attempted, and returns a safe value so one
--- bad request never kills a thread, leaves a player with a hanging UI, or
--- takes the resource down. Debug mode additionally logs every call with
--- its arguments, result and duration.

TbSafe = {}

--- Callbacks whose arguments must never appear in a log line.
local REDACTED_ARGS = {
	['tiltann_banking:atm:unlock'] = true,
	['tiltann_banking:cards:setPin'] = true,
}

local function Traceback(err)
	return debug.traceback(tostring(err), 2)
end

--- Runs `fn(...)` and never throws. On failure the error (with traceback)
--- is logged under `scope`.
---@param scope string What is being attempted, e.g. 'savings:interest'.
---@param fn function
---@param ... any
---@return boolean ok
---@return any ... The function's results, or the error string when ok is false.
function TbSafe.Run(scope, fn, ...)
	local results = table.pack(xpcall(fn, Traceback, ...))

	if not results[1] then
		TbLogger.Error(scope, 'unhandled error', { error = results[2] })
		return false, results[2]
	end

	return true, table.unpack(results, 2, results.n)
end

-- Per-player call budget across every callback: a window of RATE_WINDOW_MS
-- allows RATE_MAX_CALLS. Opening the terminal needs a handful of calls, so a
-- real player never gets near this, a script hammering the callbacks does.
local RATE_WINDOW_MS = 2000
local RATE_MAX_CALLS = 25
local rate = {}
local rateCleanupRegistered = false

--- Whether this player is still inside their call budget.
---@param source integer
---@return boolean allowed
local function WithinRateLimit(source)
	local now = GetGameTimer()
	local entry = rate[source]

	if not entry or now - entry.windowStart > RATE_WINDOW_MS then
		rate[source] = { windowStart = now, count = 1 }
		return true
	end

	entry.count = entry.count + 1
	return entry.count <= RATE_MAX_CALLS
end

--- Server: registers an ox_lib callback with an error boundary. A failing
--- handler answers `false, 'internal_error'` (the shape every mutating
--- callback already uses) instead of leaving the client's await hanging.
---@param name string
---@param handler fun(source: integer, ...): any
function TbSafe.Callback(name, handler)
	if not rateCleanupRegistered then
		rateCleanupRegistered = true

		AddEventHandler('playerDropped', function()
			rate[source] = nil
		end)
	end

	lib.callback.register(name, function(source, ...)
		local started = GetGameTimer()

		if type(source) ~= 'number' or source <= 0 then
			return false, 'internal_error'
		end

		if not WithinRateLimit(source) then
			TbLogger.Warn('callback', ('%s rate limited'):format(name), { source = source }, source)
			return false, 'rate_limited'
		end
		local results = table.pack(xpcall(handler, Traceback, source, ...))

		if not results[1] then
			TbLogger.Error('callback', ('%s failed'):format(name), { source = source, error = results[2] }, source)
			return false, 'internal_error'
		end

		if TbLogger.IsDebug() then
			TbLogger.Debug('callback', name, {
				source = source,
				ms = GetGameTimer() - started,
				args = REDACTED_ARGS[name] and '<redacted>' or table.pack(...),
				result = results[2],
			}, source)
		end

		return table.unpack(results, 2, results.n)
	end)
end

--- Server: RegisterCommand with an error boundary.
---@param name string
---@param handler fun(source: integer, args: string[], raw: string)
---@param restricted boolean
function TbSafe.Command(name, handler, restricted)
	RegisterCommand(name, function(source, args, raw)
		TbLogger.Debug('command', name, { source = source, args = args })
		TbSafe.Run(('command:%s'):format(name), handler, source, args, raw)
	end, restricted)
end

--- A background loop that survives its own errors: each pass is boxed, a
--- failing pass is logged and the next one still runs.
---@param scope string
---@param intervalMs integer
---@param fn function
function TbSafe.Loop(scope, intervalMs, fn)
	CreateThread(function()
		while true do
			Wait(intervalMs)

			local started = GetGameTimer()
			local ok = TbSafe.Run(scope, fn)

			if ok then
				TbLogger.Debug(scope, 'tick', { ms = GetGameTimer() - started })
			end
		end
	end)
end

--- Client: RegisterNUICallback with an error boundary. A failing handler
--- still answers the NUI (`ok = false, errorKey = 'internal_error'`) so the
--- React side never waits forever on a button that silently died.
---@param name string
---@param handler fun(data: table, cb: fun(result: any))
function TbSafe.Nui(name, handler)
	RegisterNUICallback(name, function(data, cb)
		local answered = false
		local function answerOnce(result)
			if not answered then
				answered = true
				cb(result)
			end
		end

		TbLogger.Debug('nui', name, { data = data })

		local ok = TbSafe.Run(('nui:%s'):format(name), handler, data, answerOnce)

		if not ok then
			answerOnce({ ok = false, errorKey = 'internal_error' })
		end
	end)
end
