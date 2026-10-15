--- @module server.society.members
--- Callbacks for the Business tab's Staff panel. Every mutation requires the
--- caller's role on THAT account to carry `manageStaff`, re-checked on each
--- call via TbSocietyPermissions, never trusted from the client. Nobody can
--- grant a role above their own (an admin can't mint owners).
---
--- Staff are ADDED by the target's online server id, not by identifier:
--- nobody reads identifiers off a screen, and an identifier typed by hand
--- silently creates a membership row for a player who may not exist. The id
--- is resolved to a real, connected player here, and their RP name is stored
--- alongside so the list stays readable once they log off. Existing members
--- are then addressed by identifier, which is the stable key.

local ROLE_RANK = { contributor = 1, admin = 2, owner = 3 }

--- Whether `actorRole` may assign `targetRole`.
---@param actorRole TbRole?
---@param targetRole TbRole?
---@return boolean
local function CanAssign(actorRole, targetRole)
	return actorRole ~= nil and targetRole ~= nil and ROLE_RANK[targetRole] ~= nil and ROLE_RANK[targetRole] <= ROLE_RANK[actorRole]
end

--- Resolves a server id to a connected player.
---@param serverId integer
---@return string? identifier
---@return string? displayName The player's RP name ("Max Mustermann").
local function ResolveOnlinePlayer(serverId)
	return TbFramework.GetIdentifier(serverId), TbFramework.GetName(serverId)
end

--- The caller's role on the account, plus whether it lets them manage staff.
---@param source integer
---@param accountId integer
---@return TbRole? role
---@return boolean canManage
local function ActorRole(source, accountId)
	local role = TbSocietyPermissions.GetRole(source, accountId)
	return role, TbSocietyPermissions.RoleToCapabilities(role).manageStaff == true
end

TbSafe.Callback('tiltann_banking:society:listMembers', function(source, accountId)
	accountId = tonumber(accountId)

	if not accountId or not TbSocietyPermissions.GetCapabilities(source, accountId).manageStaff then
		return { allowed = false }
	end

	return { allowed = true, members = TbSocietyPermissions.ListMembers(accountId) }
end)

--- Adds a staff member by their ONLINE server id.
TbSafe.Callback('tiltann_banking:society:addMember', function(source, accountId, serverId, role)
	accountId = tonumber(accountId)
	serverId = tonumber(serverId)

	if not accountId or not serverId then
		return false, 'society_invalid_member'
	end

	local actorRole, canManage = ActorRole(source, accountId)

	if not canManage then
		return false, 'society_no_permission'
	end

	if not CanAssign(actorRole, role) then
		return false, 'society_role_too_high'
	end

	-- Resolve before writing: a mistyped id has to fail here rather than
	-- create a membership row for an identifier that belongs to nobody.
	local targetIdentifier, targetName = ResolveOnlinePlayer(serverId)

	if not targetIdentifier then
		return false, 'society_player_not_online'
	end

	local identifier = TbFramework.GetIdentifier(source)

	if targetIdentifier == identifier then
		return false, 'society_cannot_add_self'
	end

	local ok = TbSocietyPermissions.AddMember(accountId, targetIdentifier, role, identifier, targetName)

	if ok and TbLog then
		TbLog('admin_actions', 'Business staff added', {
			{ name = 'Business', value = tostring(accountId) },
			{ name = 'By', value = identifier or '?' },
			{ name = 'Member', value = ('%s (%s)'):format(targetName or '?', targetIdentifier) },
			{ name = 'Role', value = role },
		})
	end

	return ok, ok and nil or 'society_invalid_member'
end)

--- Changes an existing member's role. Addressed by identifier, since the
--- member need not be online to be demoted or promoted.
TbSafe.Callback('tiltann_banking:society:setMemberRole', function(source, accountId, targetIdentifier, role)
	accountId = tonumber(accountId)

	if not accountId or type(targetIdentifier) ~= 'string' or targetIdentifier == '' then
		return false, 'society_invalid_member'
	end

	local actorRole, canManage = ActorRole(source, accountId)

	if not canManage then
		return false, 'society_no_permission'
	end

	local target = TbSocietyPermissions.GetMemberRow(targetIdentifier, accountId)

	if not target then
		return false, 'society_invalid_member'
	end

	-- Both the role they hold now and the one being handed out must be at or
	-- below the actor's own, so an admin can neither promote to owner nor
	-- demote an owner.
	if not CanAssign(actorRole, target.role) or not CanAssign(actorRole, role) then
		return false, 'society_role_too_high'
	end

	local identifier = TbFramework.GetIdentifier(source)
	local ok = TbSocietyPermissions.AddMember(accountId, targetIdentifier, role, identifier, nil)

	if ok and TbLog then
		TbLog('admin_actions', 'Business staff role changed', {
			{ name = 'Business', value = tostring(accountId) },
			{ name = 'By', value = identifier or '?' },
			{ name = 'Member', value = targetIdentifier },
			{ name = 'Role', value = role },
		})
	end

	return ok, ok and nil or 'society_invalid_member'
end)

TbSafe.Callback('tiltann_banking:society:removeMember', function(source, accountId, targetIdentifier)
	accountId = tonumber(accountId)

	if not accountId or type(targetIdentifier) ~= 'string' then
		return false, 'society_invalid_member'
	end

	local actorRole, canManage = ActorRole(source, accountId)

	if not canManage then
		return false, 'society_no_permission'
	end

	local target = TbSocietyPermissions.GetMemberRow(targetIdentifier, accountId)

	if target and not CanAssign(actorRole, target.role) then
		return false, 'society_role_too_high'
	end

	return TbSocietyPermissions.RemoveMember(accountId, targetIdentifier), nil
end)

TbSafe.Callback('tiltann_banking:society:setMemberCardLimit', function(source, accountId, targetIdentifier, limit)
	accountId = tonumber(accountId)
	limit = tonumber(limit)

	if not accountId or type(targetIdentifier) ~= 'string' then
		return false, 'society_invalid_member'
	end

	if not TbSocietyPermissions.GetCapabilities(source, accountId).manageStaff then
		return false, 'society_no_permission'
	end

	if limit and limit < 0 then
		return false, 'tx_invalid_amount'
	end

	return TbSocietyPermissions.SetMemberCardLimit(accountId, targetIdentifier, limit and math.floor(limit) or nil), nil
end)

--- The job grades behind a job-linked business, with the role each one gets
--- and what every role may do. A standalone business (no ESX job) has no
--- grades, and answers with an empty list rather than an error.
TbSafe.Callback('tiltann_banking:society:listGradeRoles', function(source, accountId)
	accountId = tonumber(accountId)

	if not accountId or not TbSocietyPermissions.GetCapabilities(source, accountId).manageStaff then
		return { allowed = false }
	end

	local account = TbAccounts.GetById(accountId)

	if not account or not account.jobName then
		return { allowed = true, jobName = nil, grades = {}, capabilities = Config.Society.RoleCapabilities }
	end

	return {
		allowed = true,
		jobName = account.jobName,
		jobLabel = TbSocietyPermissions.GetJobLabel(account.jobName),
		highestIsOwner = Config.Society.HighestGradeIsOwner == true,
		grades = TbSocietyPermissions.ListGradeRoles(account.jobName),
		capabilities = Config.Society.RoleCapabilities,
	}
end)

--- Points a job grade at a role. Everyone on that grade gets it immediately,
--- without being added as staff.
TbSafe.Callback('tiltann_banking:society:setGradeRole', function(source, accountId, grade, role)
	accountId = tonumber(accountId)
	grade = tonumber(grade)

	if not accountId or not grade then
		return false, 'society_invalid_member'
	end

	local actorRole, canManage = ActorRole(source, accountId)

	if not canManage then
		return false, 'society_no_permission'
	end

	if not CanAssign(actorRole, role) then
		return false, 'society_role_too_high'
	end

	local account = TbAccounts.GetById(accountId)

	if not account or not account.jobName then
		return false, 'society_invalid_member'
	end

	local ok = TbSocietyPermissions.SetJobRole(account.jobName, math.floor(grade), role)

	if ok and TbLog then
		TbLog('admin_actions', 'Job grade role changed', {
			{ name = 'Job', value = account.jobName },
			{ name = 'Grade', value = tostring(grade) },
			{ name = 'Role', value = role },
			{ name = 'By', value = TbFramework.GetIdentifier(source) or '?' },
		})
	end

	return ok, ok and nil or 'society_invalid_member'
end)

-- Admin test commands -------------------------------------------------------
-- /banksociety                  list the jobs
-- /banksociety <job> [role]     add yourself to that job's business (default role: owner)
-- /banksocietyleave <id|job|name>     remove yourself again

local function Reply(source, message)
	TriggerClientEvent('ox_lib:notify', source, { type = 'inform', description = message, duration = 8000 })
end

--- Finds the business account of a job, by id, job name or (part of) a name.
--- Business accounts are only created once somebody with that job opens the
--- bank, so a job nobody has used yet has no row. For those the account is
--- created here, from the ESX job list.
---@param query string
---@return table? account
local function FindSociety(query)
	local ok, rows = TbDb.SelectMany("SELECT * FROM tb_accounts WHERE type = 'society' AND deleted_at IS NULL ORDER BY name ASC")
	local lowered = query:lower()
	local partial = nil

	for _, row in ipairs(ok and rows or {}) do
		if tostring(row.id) == query or (row.job_name and row.job_name:lower() == lowered) or row.name:lower() == lowered then
			return row
		end

		if not partial and row.name:lower():find(lowered, 1, true) then
			partial = row
		end
	end

	local jobs = TbFramework.GetJobs()
	local jobName = nil

	for name, job in pairs(jobs) do
		if name:lower() == lowered or (job.label and job.label:lower() == lowered) then
			jobName = name
			break
		end
	end

	if jobName then
		local account = TbAccounts.GetOrCreateJobAccount(jobName, jobs[jobName].label)

		if account then
			local found, row = TbDb.SelectOne('SELECT * FROM tb_accounts WHERE id = ?', { account.id })
			return found and row or nil
		end
	end

	return partial
end

RegisterCommand('banksociety', function(source, args)
	if source == 0 or not TbAdmin.Is(source) then
		return
	end

	if not args[1] then
		local names = {}

		for name in pairs(TbFramework.GetJobs()) do
			names[#names + 1] = name
		end

		table.sort(names)
		print(('[tiltann_banking] jobs you can join with /banksociety <job> [role]:\n%s'):format(table.concat(names, ', ')))
		Reply(source, 'Usage: /banksociety <job> [contributor|admin|owner]\nJobs: ' .. table.concat(names, ', '))
		return
	end

	-- Any word that is a role is the role, the last other word is the job, so
	-- "/banksociety ambulance admin" and "/banksociety police ambulance" both work.
	local role, query = TbEnums.Role.OWNER, args[1]

	for _, word in ipairs(args) do
		if Config.Society.RoleCapabilities[word:lower()] then
			role = word:lower()
		else
			query = word
		end
	end

	local row = FindSociety(query)

	if not row then
		Reply(source, 'No such job. /banksociety lists them.')
		return
	end

	local identifier = TbFramework.GetIdentifier(source)

	if not identifier then
		return
	end

	local ok = TbSocietyPermissions.AddMember(row.id, identifier, role, identifier, TbFramework.GetName(source))

	Reply(source, ok and ('You are now %s of %s.'):format(role, row.name) or 'Could not add you.')

	if ok and TbLog then
		TbLog('admin_actions', 'Admin added themselves to a business', {
			{ name = 'Business', value = tostring(row.id) },
			{ name = 'Admin', value = identifier },
			{ name = 'Role', value = role },
		})
	end
end, false)

RegisterCommand('banksocietyleave', function(source, args)
	if source == 0 or not TbAdmin.Is(source) or not args[1] then
		return
	end

	local row = FindSociety(args[1])
	local identifier = TbFramework.GetIdentifier(source)

	if not row or not identifier then
		Reply(source, 'No business found.')
		return
	end

	TbSocietyPermissions.RemoveMember(row.id, identifier)
	Reply(source, ('Removed from %s.'):format(row.name))
end, false)
