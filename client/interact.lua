-- Interaction without ox_target: the standard GTA help text in the top left
-- plus the E key. Used when Config.Interaction.Mode is 'helpnotification',
-- or 'auto' without ox_target running.

TbInteract = {}

local function ShowHelp(text)
	BeginTextCommandDisplayHelp('STRING')
	AddTextComponentSubstringPlayerName(text)
	EndTextCommandDisplayHelp(0, false, true, -1)
end

local reported = {}

--- Logs a failing proximity check once per distinct message, it runs twice a
--- second and would otherwise flood the console.
---@param err any
local function ReportCheckError(err)
	local message = tostring(err)

	if reported[message] then
		return
	end

	reported[message] = true
	TbLogger.Error('interact', 'proximity check failed', { error = message })
end

--- Shows `label` while the player is near something and calls `onUse` when
--- they press the key.
---@param isNear fun(playerCoords: vector3): boolean
---@param label string
---@param onUse fun()
function TbInteract.Watch(isNear, label, onUse)
	local text = Config.Interaction.Key == 38 and ('~INPUT_PICKUP~ %s'):format(label) or label

	CreateThread(function()
		while true do
			local near = false
			local ok, result = pcall(isNear, GetEntityCoords(PlayerPedId()))

			if not ok then
				ReportCheckError(result)
			elseif result then
				near = true
			end

			if not near then
				Wait(500)
			else
				-- near: draw every frame, look again for the object twice a second
				local recheckAt = GetGameTimer() + 500

				while GetGameTimer() < recheckAt do
					Wait(0)
					ShowHelp(text)

					if IsControlJustPressed(0, Config.Interaction.Key) then
						TbSafe.Run('interact:use', onUse)
						break
					end
				end
			end
		end
	end)
end

--- Marker + help text + key inside a sphere (ox_lib zone), for places without
--- ox_target. The marker only draws while the player is in range.
---@param coords vector3
---@param radius number
---@param label string
---@param onUse fun()
function TbInteract.Zone(coords, radius, label, onUse)
	local text = Config.Interaction.Key == 38 and ('~INPUT_PICKUP~ %s'):format(label) or label

	lib.zones.sphere({
		coords = coords,
		radius = radius,
		debug = false,
		inside = function()
			DrawMarker(2, coords.x, coords.y, coords.z + 0.2, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0, 0.3, 0.3, 0.3, 79, 140, 255, 160, true, true, 2, false, nil, nil, false)
			ShowHelp(text)

			if IsControlJustPressed(0, Config.Interaction.Key) then
				TbSafe.Run('interact:use', onUse)
			end
		end,
	})
end

-- Mode = 'custom': hand the player's own code the functions that open the screens.
CreateThread(function()
	if Config.Interaction.Mode ~= 'custom' or type(Config.Interaction.Custom) ~= 'function' then
		return
	end

	TbSafe.Run('interact:custom', Config.Interaction.Custom, function() TbOpenAtm() end, function() TbOpenTerminal() end, function() TbOpenBilling() end)
end)
