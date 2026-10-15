--- @module shared.logger
--- One logging entry point for both sides. Every line carries a level, a
--- scope (the module / concern) and optional structured data, printed as
--- `[tiltann_banking] [LEVEL] [scope] message | key=value ...`.
---
--- Server-side, info/warn/error lines are also forwarded to ox_lib's logger
--- (lib.logger) when Config.Logs.OxLogger.Enabled, which ships them to
--- Datadog / Loki / Fivemanage depending on the `ox:logger` convar. Debug
--- lines only print, and only while Config.Logs.Debug is true (toggle at
--- runtime with /tb_debug).

TbLogger = {}

local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }
local COLORS = { debug = '^6', info = '^5', warn = '^3', error = '^1' }
local MAX_VALUE_LENGTH = 400
local repeats = {}

---@return boolean
function TbLogger.IsDebug()
	return Config.Logs ~= nil and Config.Logs.Debug == true
end

---@param enabled boolean
function TbLogger.SetDebug(enabled)
	Config.Logs.Debug = enabled == true
end

--- Renders one data value for a log line. Tables go through json.encode
--- (guarded, a userdata inside must not take the log line down with it).
---@param value any
---@return string
local function RenderValue(value)
	local rendered

	if type(value) == 'table' then
		local ok, encoded = pcall(json.encode, value)
		rendered = ok and encoded or '<unencodable table>'
	else
		rendered = tostring(value)
	end

	if #rendered > MAX_VALUE_LENGTH then
		rendered = rendered:sub(1, MAX_VALUE_LENGTH) .. '…'
	end

	return rendered
end

--- Turns a data table into ` | a=1 b=x` plus a list of `key:value` tags for ox_lib.
---@param data table?
---@return string suffix
---@return string[] tags
local function RenderData(data)
	if type(data) ~= 'table' or next(data) == nil then
		return '', {}
	end

	local keys = {}

	for key in pairs(data) do
		keys[#keys + 1] = tostring(key)
	end

	table.sort(keys)

	local parts, tags = {}, {}

	for i, key in ipairs(keys) do
		local rendered = RenderValue(data[key])
		parts[i] = ('%s=%s'):format(key, rendered)
		tags[i] = ('%s:%s'):format(key, rendered)
	end

	return ' | ' .. table.concat(parts, ' '), tags
end

---@param level 'debug'|'info'|'warn'|'error'
---@param scope string
---@param message string
---@param data table?
---@param source integer? Player the line concerns (ox_lib attaches their identifiers).
local function Emit(level, scope, message, data, source)
	local logs = Config.Logs or {}

	if level == 'debug' and not logs.Debug then
		return
	end

	local minimum = LEVELS[(logs.Console and logs.Console.Level) or 'info'] or LEVELS.info
	local suffix, tags = RenderData(data)

	local quietLedger = scope == 'ledger' and level == 'info' and not (logs.Console and logs.Console.Ledger)

	-- The same warning or error over and over (a poll that keeps failing) is
	-- printed once a minute with a count instead of on every pass.
	if (level == 'warn' or level == 'error') and IsDuplicityVersion() then
		local key = ('%s|%s|%s'):format(level, scope, message)
		local now = GetGameTimer()
		local seen = repeats[key]

		if seen and now - seen.at < 60000 then
			seen.count = seen.count + 1
			return
		end

		if seen and seen.count > 0 then
			message = ('%s (repeated %d times)'):format(message, seen.count)
		end

		repeats[key] = { at = now, count = 0 }
	end

	if not quietLedger and (level == 'debug' or LEVELS[level] >= minimum) then
		print(('%s[tiltann_banking]^7 [%s] [%s] %s%s'):format(COLORS[level], level:upper(), scope, message, suffix))
	end

	if level ~= 'debug' and IsDuplicityVersion() and logs.OxLogger and logs.OxLogger.Enabled and lib and lib.logger then
		-- ox_lib's logger is itself a no-op unless the `ox:logger` convar
		-- names a backend; guarded anyway so a backend hiccup never reaches
		-- the money flow that logged.
		pcall(lib.logger, source, ('%s.%s'):format(scope, level), message, table.unpack(tags))
	end
end

---@param scope string
---@param message string
---@param data table?
---@param source integer?
function TbLogger.Debug(scope, message, data, source)
	Emit('debug', scope, message, data, source)
end

---@param scope string
---@param message string
---@param data table?
---@param source integer?
function TbLogger.Info(scope, message, data, source)
	Emit('info', scope, message, data, source)
end

---@param scope string
---@param message string
---@param data table?
---@param source integer?
function TbLogger.Warn(scope, message, data, source)
	Emit('warn', scope, message, data, source)
end

---@param scope string
---@param message string
---@param data table?
---@param source integer?
function TbLogger.Error(scope, message, data, source)
	Emit('error', scope, message, data, source)
end
