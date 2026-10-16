--- @module server.logging.webhook
--- Discord logging. Every module calls TbLog(category, title, fields). One
--- webhook (Config.Logs.Webhook) gets everything, the category shows as an
--- icon and colour on the embed. Big amounts are also posted to the security
--- webhook (Config.Logs.SecurityWebhook, falls back to the main one). A
--- category can still get its own channel through Config.Logs.WebhookURLs.
---
--- Embeds are queued and sent in batches (Discord allows 10 per message and
--- about 30 messages a minute), so a burst of payments never gets throttled.
--- A logging failure is reported through TbLogger and never reaches the money
--- flow that called it.

---@class TbLogField
---@field name string
---@field value string
---@field inline boolean?

local CATEGORY_STYLE = {
	deposits = { icon = '💵', color = 0x3ecf8e },
	withdrawals = { icon = '🏧', color = 0xe5a83d },
	transfers = { icon = '🔁', color = 0x4f8cff },
	cards = { icon = '💳', color = 0x9b6bff },
	loans = { icon = '🏦', color = 0x2fb7c4 },
	tax = { icon = '🏛️', color = 0x8b909c },
	billing = { icon = '🧾', color = 0xe58a3d },
	admin_actions = { icon = '🛠️', color = 0xe5a83d },
	society_sync = { icon = '🔄', color = 0x8b909c },
	security_alerts = { icon = '🚨', color = 0xe5484d },
}

-- Fields that hold money, checked against Config.Logs.LargeTransactionThreshold.
local AMOUNT_FIELDS = { amount = true, delta = true, ['new balance'] = true, total = true }

local FLUSH_MS = 5000
local MAX_EMBEDS = 10

---@type table<string, table[]> queued embeds per webhook url
local queues = {}
local flushStarted = false

local function Send(url, embeds)
	local ok, body = pcall(json.encode, { username = Config.Logs.BotName, embeds = embeds })

	if not ok then
		TbLogger.Error('webhook', 'failed to encode payload', { error = body })
		return
	end

	PerformHttpRequest(url, function(status)
		if type(status) ~= 'number' or status < 200 or status >= 300 then
			TbLogger.Warn('webhook', 'Discord returned a non-2xx status', { status = status })
		end
	end, 'POST', body, { ['Content-Type'] = 'application/json' })
end

local function Flush()
	for url, queue in pairs(queues) do
		while #queue > 0 do
			local batch = {}

			for _ = 1, math.min(MAX_EMBEDS, #queue) do
				batch[#batch + 1] = table.remove(queue, 1)
			end

			Send(url, batch)
		end

		queues[url] = nil
	end
end

local function Enqueue(url, embed)
	queues[url] = queues[url] or {}
	table.insert(queues[url], embed)

	if #queues[url] >= MAX_EMBEDS then
		Flush()
	end

	if not flushStarted then
		flushStarted = true

		CreateThread(function()
			while true do
				Wait(FLUSH_MS)
				TbSafe.Run('webhook:flush', Flush)
			end
		end)
	end
end

--- Online players by identifier, so a log shows "Max Mustermann (ID 12)"
--- instead of a long identifier string.
---@return table<string, string>
local function OnlineNames()
	local names = {}

	for _, player in ipairs(TbFramework.GetPlayers()) do
		names[player.identifier] = ('%s (ID %d)'):format(TbFramework.GetName(player.source) or 'Unknown', player.source)
	end

	return names
end

---@param fields TbLogField[]
---@return TbLogField[]
local function Prettify(fields)
	local names = OnlineNames()
	local result = {}

	for i, field in ipairs(fields or {}) do
		local value = tostring(field.value)

		result[i] = {
			name = tostring(field.name),
			value = names[value] and ('%s\n`%s`'):format(names[value], value) or value,
			inline = field.inline ~= false,
		}
	end

	return result
end

---@param fields TbLogField[]
---@return boolean
local function IsLarge(fields)
	for _, field in ipairs(fields or {}) do
		if AMOUNT_FIELDS[tostring(field.name):lower()] then
			local number = tonumber((tostring(field.value):gsub('[^%d%-]', '')))

			if number and math.abs(number) >= Config.Logs.LargeTransactionThreshold then
				return true
			end
		end
	end

	return false
end

local function UrlFor(category)
	local url = Config.Logs.WebhookURLs[category]

	if category == 'security_alerts' and (not url or url == '') then
		url = Config.Logs.SecurityWebhook
	end

	if not url or url == '' then
		url = Config.Logs.Webhook
	end

	return url ~= '' and url or nil
end

local function BuildEmbed(category, title, fields, colorOverride)
	local style = CATEGORY_STYLE[category] or { icon = '📄', color = Config.Logs.Colors.info }

	return {
		title = ('%s %s'):format(style.icon, title),
		color = colorOverride or style.color,
		fields = Prettify(fields),
		footer = { text = ('%s | tiltann_banking v%s'):format(category, GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '0.0.0') },
		timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
	}
end

---@param category string One of the keys in Config.Logs.Enabled.
---@param title string
---@param fields TbLogField[]
---@param colorOverride integer?
local function WriteLog(category, title, fields, colorOverride)
	-- The console and ox_lib logger always see the event, webhook or not.
	local data = {}

	for _, field in ipairs(fields or {}) do
		data[tostring(field.name):lower():gsub('%s+', '_')] = field.value
	end

	TbLogger.Debug(category, title, data)

	if not Config.Logs.Enabled[category] then
		return
	end

	local url = UrlFor(category)

	if url then
		Enqueue(url, BuildEmbed(category, title, fields, colorOverride))
	end

	-- A large amount is also posted to the security channel, once.
	if category ~= 'security_alerts' and Config.Logs.Enabled.security_alerts and IsLarge(fields) then
		local alertUrl = UrlFor('security_alerts')

		if alertUrl then
			local embed = BuildEmbed('security_alerts', ('Large amount: %s'):format(title), fields, Config.Logs.Colors.warning)
			embed.description = ('Category: `%s`'):format(category)
			Enqueue(alertUrl, embed)
		end
	end
end

function TbLog(category, title, fields, colorOverride)
	TbSafe.Run('webhook', WriteLog, category, title, fields, colorOverride)
end
