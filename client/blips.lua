--- @module client.blips
--- Map blips for the banks (and optionally every ATM) from the config.
--- Created once on start. Every bank blip can have its own sprite, colour,
--- scale and label, see Config.Bank.Blips.Locations.

---@param coords vector3
---@param style table Sprite, Colour, Scale, Display, ShortRange (Capitalised) with optional lowercase overrides.
---@param label string
local function CreateBlip(coords, style, label)
	if not coords then
		return
	end

	local blip = AddBlipForCoord(coords.x, coords.y, coords.z)

	SetBlipSprite(blip, style.sprite or style.Sprite)
	SetBlipDisplay(blip, style.display or style.Display or 4)
	SetBlipScale(blip, style.scale or style.Scale)
	SetBlipColour(blip, style.colour or style.Colour)
	SetBlipAsShortRange(blip, style.shortRange == nil and style.ShortRange or style.shortRange)
	BeginTextCommandSetBlipName('STRING')
	AddTextComponentSubstringPlayerName(label)
	EndTextCommandSetBlipName(blip)
end

CreateThread(function()
	local banks = Config.Bank.Blips

	if banks.Enabled then
		-- no Locations listed: one blip at every terminal zone
		local locations = #banks.Locations > 0 and banks.Locations or Config.Bank.Zones

		for _, location in ipairs(locations) do
			TbSafe.Run('blips:bank', CreateBlip, location.coords, setmetatable(location, { __index = banks }), location.label or banks.Label)
		end
	end

	local atms = Config.Bank.AtmBlips

	if atms.Enabled then
		for _, coords in ipairs(atms.Coords) do
			TbSafe.Run('blips:atm', CreateBlip, coords, atms, atms.Label)
		end
	end
end)
