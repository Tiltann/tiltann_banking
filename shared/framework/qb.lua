-- QBCore implementation of the framework layer. NOT TESTED, see the warning
-- TbFramework prints when it is selected.
--
-- QBCore and Qbox share the same player data shape, so the functions are built
-- once here (TbQbLike.Build) and shared/framework/qbox.lua only supplies
-- different accessors.

TbQbLike = {}

---@param name string 'qb' or 'qbox'
---@param api { ready: fun(), player: fun(source: integer): table?, players: fun(): table, byCitizenId: fun(id: string): table?, jobs: fun(): table }
function TbQbLike.Build(name, api)
	local Impl = { Experimental = true }

	function Impl.Ready()
		api.ready()
	end

	if not IsDuplicityVersion() then
		-- Calls cb whenever the player's bank balance changes.
		function Impl.OnBankChanged(cb)
			RegisterNetEvent('QBCore:Client:OnMoneyChange', function(moneyType)
				if moneyType == 'bank' then
					cb()
				end
			end)
		end

		TbFramework.Register(name, Impl)
		return
	end

	local function Data(source)
		local ok, player = pcall(api.player, source)
		return ok and player and player.PlayerData or nil, ok and player or nil
	end

	function Impl.GetIdentifier(source)
		local data = Data(source)
		return data and data.citizenid or nil
	end

	function Impl.GetName(source)
		local data = Data(source)

		if not data or not data.charinfo then
			return nil
		end

		local full = ('%s %s'):format(data.charinfo.firstname or '', data.charinfo.lastname or ''):gsub('^%s+', ''):gsub('%s+$', '')
		return full ~= '' and full or nil
	end

	function Impl.GetJob(source)
		local data = Data(source)

		if not data or not data.job or not data.job.name then
			return nil
		end

		local grade = type(data.job.grade) == 'table' and data.job.grade.level or data.job.grade
		return { name = data.job.name, label = data.job.label, grade = tonumber(grade) or 0 }
	end

	function Impl.GetCash(source)
		local data = Data(source)
		return data and data.money and data.money.cash or nil
	end

	function Impl.AddCash(source, amount)
		local _, player = Data(source)
		return player ~= nil and player.Functions.AddMoney('cash', amount, 'tiltann_banking') == true
	end

	function Impl.RemoveCash(source, amount)
		local data, player = Data(source)

		if not data or not data.money or data.money.cash < amount then
			return false
		end

		return player.Functions.RemoveMoney('cash', amount, 'tiltann_banking') == true
	end

	function Impl.GetPlayers()
		local list = {}
		local ok, players = pcall(api.players)

		if ok and type(players) == 'table' then
			for _, player in pairs(players) do
				local data = player.PlayerData

				if data and data.source and data.citizenid then
					list[#list + 1] = { source = data.source, identifier = data.citizenid }
				end
			end
		end

		return list
	end

	function Impl.GetSourceByIdentifier(identifier)
		local ok, player = pcall(api.byCitizenId, identifier)
		return ok and player and player.PlayerData and player.PlayerData.source or nil
	end

	function Impl.GetJobs()
		local jobs = {}
		local ok, raw = pcall(api.jobs)

		if not ok or type(raw) ~= 'table' then
			return jobs
		end

		for jobName, job in pairs(raw) do
			local grades = {}

			for key, grade in pairs(job.grades or {}) do
				local number = tonumber(key)

				if number then
					grades[#grades + 1] = { grade = number, label = grade.name or tostring(number) }
				end
			end

			jobs[jobName] = { label = job.label or jobName, grades = grades }
		end

		return jobs
	end

	function Impl.HasGroup(source, group)
		local ok, allowed = pcall(api.hasPermission, source, group)
		return ok and allowed == true
	end

	Impl.BankTarget = 'framework_bank'

	function Impl.GetBank(source)
		local data = Data(source)
		return data and data.money and data.money.bank or nil
	end

	function Impl.SetBank(source, amount)
		local _, player = Data(source)
		return player ~= nil and player.Functions.SetMoney('bank', amount, 'tiltann_banking') == true
	end

	function Impl.SetBankOffline(identifier, amount)
		return TbDb.Update("UPDATE players SET money = JSON_SET(money, '$.bank', ?) WHERE citizenid = ?", { amount, identifier }) == true
	end

	-- No society mirror yet. Business money stays inside tiltann_banking only.
	function Impl.GetSocietyTargets()
		return {}
	end

	TbFramework.Register(name, Impl)
end

local function GetCore()
	return exports['qb-core']:GetCoreObject()
end

TbQbLike.Build('qb', {
	ready = function()
		local deadline = GetGameTimer() + 15000

		while not pcall(GetCore) do
			if GetGameTimer() >= deadline then
				error('qb-core did not start, is it ensured before tiltann_banking?', 0)
			end

			Wait(100)
		end
	end,
	player = function(source)
		return GetCore().Functions.GetPlayer(source)
	end,
	players = function()
		return GetCore().Functions.GetQBPlayers()
	end,
	byCitizenId = function(citizenId)
		return GetCore().Functions.GetPlayerByCitizenId(citizenId)
	end,
	jobs = function()
		return GetCore().Shared.Jobs
	end,
	hasPermission = function(source, group)
		return GetCore().Functions.HasPermission(source, group)
	end,
})
