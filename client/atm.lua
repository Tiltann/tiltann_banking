-- ATM interaction. Works on the ATM props already in the map and on any
-- Config.Atm.Locations, through ox_target or the help text (Config.Interaction).

local function NearAtm(playerCoords, propHashes)
	for _, location in ipairs(Config.Atm.Locations) do
		if #(playerCoords - location.coords) < Config.Atm.InteractDistance then
			return true
		end
	end

	if Config.Atm.UseExistingProps then
		for _, hash in ipairs(propHashes) do
			if GetClosestObjectOfType(playerCoords.x, playerCoords.y, playerCoords.z, Config.Atm.InteractDistance, hash, false, false, false) ~= 0 then
				return true
			end
		end
	end

	return false
end

local function SetupOxTarget()
	if not TbUtils.WaitForOxTarget() then
		TbLogger.Error('atm', 'Config.Interaction.Mode is target but ox_target is not started, ATMs cannot be used')
		return
	end

	local options = {
		{ icon = 'fas fa-money-bill-transfer', label = locale('atm_interact'), onSelect = function() TbOpenAtm() end },
	}

	if Config.Atm.UseExistingProps then
		TbSafe.Run('atm:addModel', function()
			exports.ox_target:addModel(Config.Atm.PropModels, options)
		end)
	end

	-- One zone at a time, so a broken entry in the config does not take the
	-- ones after it down.
	for _, location in ipairs(Config.Atm.Locations) do
		TbSafe.Run('atm:addZone', function()
			exports.ox_target:addBoxZone({
				coords = location.coords,
				size = vector3(1.0, 1.0, 2.0),
				rotation = location.heading or 0.0,
				options = options,
			})
		end)
	end
end

CreateThread(function()
	if Config.Interaction.Mode == 'custom' then
		return
	end

	if TbUtils.UseOxTarget() then
		SetupOxTarget()

		if not Config.Interaction.HelpText then
			return
		end
	end

	local propHashes = {}

	for _, model in ipairs(Config.Atm.PropModels) do
		propHashes[#propHashes + 1] = GetHashKey(model)
	end

	-- Props have no fixed coords, so they are polled; fixed locations get a marker zone.
	for _, location in ipairs(Config.Atm.Locations) do
		TbSafe.Run('atm:addMarker', function()
			TbInteract.Zone(location.coords, Config.Atm.InteractDistance, locale('atm_interact'), function() TbOpenAtm() end)
		end)
	end

	if Config.Atm.UseExistingProps then
		TbInteract.Watch(function(coords)
			return NearAtm(coords, propHashes)
		end, locale('atm_interact'), function() TbOpenAtm() end)
	end
end)
