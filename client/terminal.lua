-- Bank terminals: one per Config.Bank.Zones entry, plus the bank clerk peds
-- in Config.Bank.Peds. Opens the tablet UI through ox_target or the help text.

local spawnedPeds = {}

local function SpawnPed(entry)
	if not entry.model or not entry.coords then
		TbLogger.Warn('terminal', 'ped entry needs a model and coords, skipped', { model = entry.model })
		return nil
	end

	local model = type(entry.model) == 'string' and joaat(entry.model) or entry.model

	if not IsModelInCdimage(model) then
		TbLogger.Warn('terminal', 'ped model does not exist', { model = entry.model })
		return nil
	end

	RequestModel(model)

	local timeout = GetGameTimer() + 5000

	while not HasModelLoaded(model) and GetGameTimer() < timeout do
		Wait(0)
	end

	if not HasModelLoaded(model) then
		TbLogger.Warn('terminal', 'ped model did not load in time', { model = entry.model })
		SetModelAsNoLongerNeeded(model)
		return nil
	end

	local ped = CreatePed(4, model, entry.coords.x, entry.coords.y, entry.coords.z - 1.0, entry.coords.w, false, true)

	SetModelAsNoLongerNeeded(model)

	if not ped or ped == 0 then
		return nil
	end

	SetEntityInvincible(ped, true)
	SetBlockingOfNonTemporaryEvents(ped, true)
	SetPedCanRagdoll(ped, false)
	FreezeEntityPosition(ped, true)

	if entry.scenario then
		TaskStartScenarioInPlace(ped, entry.scenario, 0, true)
	end

	return ped
end

local function SpawnPeds()
	for _, entry in ipairs(Config.Bank.Peds) do
		local ok, ped = TbSafe.Run('terminal:spawnPed', SpawnPed, entry)

		if ok and ped then
			spawnedPeds[#spawnedPeds + 1] = ped
		end
	end
end

-- A ped standing at a zone is the target there; the box zone is only used
-- where no ped is, so a counter never has two targets.
local function PedNear(coords)
	for _, entry in ipairs(Config.Bank.Peds) do
		if Config.Bank.SpawnPeds and #(vector3(entry.coords.x, entry.coords.y, entry.coords.z) - coords) < 6.0 then
			return vector3(entry.coords.x, entry.coords.y, entry.coords.z)
		end
	end

	return nil
end

local function SetupInteractions()
	if Config.Interaction.Mode == 'custom' then
		return
	end

	local useTarget = TbUtils.UseOxTarget()

	if useTarget then
		if not TbUtils.WaitForOxTarget() then
			TbLogger.Error('terminal', 'Config.Interaction.Mode is target but ox_target is not started, the terminals cannot be used')
			return
		end

		local option = { icon = 'fas fa-tablet-screen-button', label = locale('terminal_interact'), onSelect = function() TbOpenTerminal() end }

		for _, zone in ipairs(Config.Bank.Zones) do
			if not PedNear(zone.coords) then
				TbSafe.Run('terminal:addZone', function()
					exports.ox_target:addBoxZone({
						coords = zone.coords,
						size = zone.size or vector3(1.5, 1.5, 2.5),
						rotation = zone.heading or 0.0,
						options = { option },
					})
				end)
			end
		end

		for _, ped in ipairs(spawnedPeds) do
			TbSafe.Run('terminal:addPed', function()
				exports.ox_target:addLocalEntity(ped, { option })
			end)
		end

		if not Config.Interaction.HelpText then
			return
		end
	end

	for _, zone in ipairs(Config.Bank.Zones) do
		TbSafe.Run('terminal:addMarker', function()
			TbInteract.Zone(PedNear(zone.coords) or zone.coords, Config.Bank.TerminalInteractDistance, locale('terminal_interact'), function() TbOpenTerminal() end)
		end)
	end
end

CreateThread(function()
	if Config.Bank.SpawnPeds then
		TbSafe.Run('terminal:peds', SpawnPeds)
	end

	TbSafe.Run('terminal:interactions', SetupInteractions)
end)

AddEventHandler('onResourceStop', function(resource)
	if resource ~= GetCurrentResourceName() then
		return
	end

	for _, ped in ipairs(spawnedPeds) do
		if DoesEntityExist(ped) then
			DeleteEntity(ped)
		end
	end
end)
