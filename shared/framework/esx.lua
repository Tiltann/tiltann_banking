-- ESX implementation of the framework layer (legacy and current es_extended).

local Esx = {}
local esx = nil

local function GetEsx()
	if esx then
		return esx
	end

	local ok, result = pcall(function()
		return exports['es_extended']:getSharedObject()
	end)

	if ok and result then
		esx = result
		return esx
	end

	-- very old builds only hand the object out through an event
	local deadline = GetGameTimer() + 15000

	while esx == nil do
		TriggerEvent('esx:getSharedObject', function(obj)
			esx = obj
		end)

		if esx == nil then
			if GetGameTimer() >= deadline then
				error('es_extended did not hand out its shared object, is it started?', 0)
			end

			Wait(100)
		end
	end

	return esx
end

-- Blocks until the framework can be used.
function Esx.Ready()
	GetEsx()
end

if not IsDuplicityVersion() then
	-- Calls cb whenever the framework changes the player's bank balance.
	function Esx.OnBankChanged(cb)
		RegisterNetEvent('esx:setAccountMoney', function(account)
			if type(account) == 'table' and account.name == 'bank' then
				cb()
			end
		end)
	end

	TbFramework.Register('esx', Esx)
	return
end

local function Player(source)
	local ok, xPlayer = pcall(function()
		return GetEsx().GetPlayerFromId(source)
	end)

	return ok and xPlayer or nil
end

---@return string? identifier nil when the player is not logged in
function Esx.GetIdentifier(source)
	local xPlayer = Player(source)
	return xPlayer and xPlayer.identifier or nil
end

---@return string? name the character name
function Esx.GetName(source)
	local xPlayer = Player(source)

	if not xPlayer then
		return nil
	end

	local ok, name = pcall(xPlayer.getName)
	return (ok and type(name) == 'string' and name ~= '') and name or nil
end

---@return { name: string, label: string?, grade: integer }?
function Esx.GetJob(source)
	local xPlayer = Player(source)

	if not xPlayer then
		return nil
	end

	local ok, job = pcall(xPlayer.getJob)

	if not ok or not job or not job.name then
		return nil
	end

	return { name = job.name, label = job.label, grade = tonumber(job.grade) or 0 }
end

---@return integer? cash
function Esx.GetCash(source)
	local xPlayer = Player(source)
	return xPlayer and xPlayer.getMoney() or nil
end

---@return boolean ok
function Esx.AddCash(source, amount)
	local xPlayer = Player(source)

	if not xPlayer then
		return false
	end

	xPlayer.addMoney(amount)
	return true
end

---@return boolean ok
function Esx.RemoveCash(source, amount)
	local xPlayer = Player(source)

	if not xPlayer or xPlayer.getMoney() < amount then
		return false
	end

	xPlayer.removeMoney(amount)
	return true
end

---@return { source: integer, identifier: string }[]
function Esx.GetPlayers()
	local list = {}
	local ok, players = pcall(function()
		return GetEsx().GetExtendedPlayers()
	end)

	if ok and players then
		for _, xPlayer in pairs(players) do
			list[#list + 1] = { source = xPlayer.source, identifier = xPlayer.identifier }
		end
	end

	return list
end

---@return integer? source nil when the identifier is offline
function Esx.GetSourceByIdentifier(identifier)
	local ok, xPlayer = pcall(function()
		return GetEsx().GetPlayerFromIdentifier(identifier)
	end)

	return ok and xPlayer and xPlayer.source or nil
end

---@return table<string, { label: string, grades: { grade: integer, label: string }[] }>
function Esx.GetJobs()
	local jobs = {}
	local ok, raw = pcall(function()
		return GetEsx().GetJobs()
	end)

	if not ok or type(raw) ~= 'table' then
		return jobs
	end

	for name, job in pairs(raw) do
		local grades = {}

		for key, grade in pairs(job.grades or {}) do
			local number = tonumber(type(grade) == 'table' and grade.grade or key)

			if number then
				grades[#grades + 1] = { grade = number, label = (type(grade) == 'table' and (grade.label or grade.name)) or tostring(number) }
			end
		end

		jobs[name] = { label = job.label or name, grades = grades }
	end

	return jobs
end

---@param group string
---@return boolean
function Esx.HasGroup(source, group)
	local xPlayer = Player(source)

	if not xPlayer then
		return false
	end

	local ok, playerGroup = pcall(xPlayer.getGroup)
	return ok and playerGroup == group
end

-- Mirror of the default personal account in the framework's own bank balance.
Esx.BankTarget = 'esx_bank'

---@return integer? balance
function Esx.GetBank(source)
	local xPlayer = Player(source)

	if not xPlayer then
		return nil
	end

	local ok, account = pcall(xPlayer.getAccount, 'bank')
	return ok and account and account.money or nil
end

---@return boolean ok
function Esx.SetBank(source, amount)
	local xPlayer = Player(source)

	if not xPlayer then
		return false
	end

	return (pcall(xPlayer.setAccountMoney, 'bank', amount))
end

-- Same as SetBank for a player who is not online.
---@return boolean ok
function Esx.SetBankOffline(identifier, amount)
	local ok, row = TbDb.SelectOne('SELECT accounts FROM users WHERE identifier = ?', { identifier })

	if not ok or not row or not row.accounts then
		return false
	end

	local decoded, accounts = pcall(json.decode, row.accounts)

	if not decoded or type(accounts) ~= 'table' then
		return false
	end

	-- Current ESX keeps { bank = 100, money = 0, ... }, older builds a list
	-- of { name = 'bank', money = 100 } entries. Handle both.
	local found = false

	if type(accounts.bank) == 'number' then
		accounts.bank = amount
		found = true
	else
		for _, entry in ipairs(accounts) do
			if type(entry) == 'table' and entry.name == 'bank' then
				entry.money = amount
				found = true
				break
			end
		end
	end

	if not found then
		return false
	end

	local encoded, body = pcall(json.encode, accounts)

	if not encoded then
		return false
	end

	return (TbDb.Update('UPDATE users SET accounts = ? WHERE identifier = ?', { body, identifier }))
end

-- Society money kept by other resources. Each target has a name (stored in
-- tb_sync_log), get(job) and set(job, amount). Only running resources are
-- returned.
---@return { name: string, get: fun(job: string): integer?, set: fun(job: string, amount: integer) }[]
function Esx.GetSocietyTargets()
	local targets = {}

	if GetResourceState('esx_addonaccount') == 'started' then
		targets[#targets + 1] = {
			name = 'esx_addonaccount',
			get = function(job)
				local shared = exports['esx_addonaccount']:GetSharedAccount('society_' .. job)
				return shared and shared.money or nil
			end,
			set = function(job, amount)
				local shared = exports['esx_addonaccount']:GetSharedAccount('society_' .. job)

				if shared then
					shared.setMoney(amount)
				end
			end,
		}
	end

	-- esx_society keeps its money in esx_addonaccount, so that one target covers both

	return targets
end

TbFramework.Register('esx', Esx)
