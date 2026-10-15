--- @module server.society.permissions
--- Who may do what with a business, via two paths that can both apply:
---
--- 1. ESX job/grade, the business linked to the player's current job.
---    Automatic, zero setup: grade -> role via tb_society_grade_roles, else
---    Config.Society.DefaultGradeRole; the job's top grade is always owner.
--- 2. Explicit staff (tb_account_members), added by someone whose role
---    allows manageStaff, independent of ESX job. This is what lets a player
---    see and use more than one business.
---
--- A role maps to capabilities through Config.Society.RoleCapabilities, so
--- both paths are judged by exactly the same rules.

TbSocietyPermissions = {}

--- Capabilities for a role, copied so callers can't mutate the config.
---@param role TbRole?
---@return TbCapabilities
function TbSocietyPermissions.RoleToCapabilities(role)
	local capabilities = role and Config.Society.RoleCapabilities[role]

	if not capabilities then
		return TbEnums.NoCapabilities
	end

	return TbUtils.ShallowCopy(capabilities)
end

--- Highest grade ESX defines for a job (the boss), via the standard
--- job_grades table every ESX build ships.
---@param jobName string
---@return integer?
local function GetHighestGrade(jobName)
	local job = TbFramework.GetJobs()[jobName]
	local highest = nil

	for _, grade in ipairs(job and job.grades or {}) do
		if not highest or grade.grade > highest then
			highest = grade.grade
		end
	end

	return highest
end

--- Role a job grade holds on its job's business.
---@param jobName string
---@param grade integer
---@return TbRole
function TbSocietyPermissions.GetJobRole(jobName, grade)
	if Config.Society.HighestGradeIsOwner then
		local highest = GetHighestGrade(jobName)

		if highest and grade >= highest then
			return TbEnums.Role.OWNER
		end
	end

	local ok, row = TbDb.SelectOne('SELECT role FROM tb_society_grade_roles WHERE job_name = ? AND grade = ?', { jobName, grade })

	if ok and row and row.role then
		return row.role
	end

	return Config.Society.DefaultGradeRole
end

--- Every grade of a job with the role it currently maps to, for the Staff
--- page's grade editor. `isHighest` marks the grade that
--- Config.Society.HighestGradeIsOwner pins to owner no matter what the
--- override table says, that is the rule that stops a boss locking
--- themselves out of their own business, so the UI shows it as fixed rather
--- than offering a control that would be ignored.
---@param jobName string
---@return table[] grades
function TbSocietyPermissions.ListGradeRoles(jobName)
	local job = TbFramework.GetJobs()[jobName]

	if not job then
		return {}
	end

	local highest = GetHighestGrade(jobName)
	local grades = {}

	for _, grade in ipairs(job.grades) do
		grades[#grades + 1] = {
			grade = grade.grade,
			label = grade.label,
			role = TbSocietyPermissions.GetJobRole(jobName, grade.grade),
			isHighest = Config.Society.HighestGradeIsOwner and highest ~= nil and grade.grade >= highest,
		}
	end

	table.sort(grades, function(a, b)
		return a.grade < b.grade
	end)

	return grades
end

--- Upserts a job grade's role override.
---@param jobName string
---@param grade integer
---@param role TbRole
---@return boolean ok
function TbSocietyPermissions.SetJobRole(jobName, grade, role)
	if not Config.Society.RoleCapabilities[role] then
		return false
	end

	return TbDb.Update(
		'INSERT INTO tb_society_grade_roles (job_name, grade, role) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE role = VALUES(role)',
		{ jobName, grade, role }
	)
end

--- The player's current ESX job business (auto-created) and their role on
--- it. `nil` if they aren't logged in or have no job with a society account.
---@param source integer
---@return TbAccount? account
---@return TbRole? role
function TbSocietyPermissions.GetJobBusiness(source)
	local job = TbFramework.GetJob(source)

	if not job or job.name == 'unemployed' then
		return nil, nil
	end

	local account = TbAccounts.GetOrCreateJobAccount(job.name, job.label)

	if not account then
		return nil, nil
	end

	return account, TbSocietyPermissions.GetJobRole(job.name, job.grade or 0)
end

--- Explicit staff row for an identifier on an account.
---@param identifier string
---@param accountId integer
---@return table? row Raw tb_account_members row.
function TbSocietyPermissions.GetMemberRow(identifier, accountId)
	local ok, row = TbDb.SelectOne('SELECT * FROM tb_account_members WHERE account_id = ? AND identifier = ?', { accountId, identifier })

	if not ok or not row then
		return nil
	end

	return row
end

--- Resolves the caller's role on one SPECIFIC business, whichever path
--- grants it. The check every business action goes through, always fresh,
--- never trusted from the client.
---@param source integer
---@param accountId integer
---@return TbRole? role `nil` = no access.
function TbSocietyPermissions.GetRole(source, accountId)
	local identifier = TbFramework.GetIdentifier(source)

	if not identifier then
		return nil
	end

	local jobAccount, jobRole = TbSocietyPermissions.GetJobBusiness(source)

	if jobAccount and jobAccount.id == accountId then
		return jobRole
	end

	local row = TbSocietyPermissions.GetMemberRow(identifier, accountId)

	return row and row.role or nil
end

---@param source integer
---@param accountId integer
---@return TbCapabilities
function TbSocietyPermissions.GetCapabilities(source, accountId)
	return TbSocietyPermissions.RoleToCapabilities(TbSocietyPermissions.GetRole(source, accountId))
end

--- The human-facing label of an ESX job ("Polizei" for `police`). Players
--- read labels, not job keys, so nothing in the UI should ever show the raw
--- name. Falls back to the name when ESX has no such job. Memoized: the job
--- table does not change at runtime and this is read on every business list.
local jobLabels = nil

---@param jobName string?
---@return string? label
function TbSocietyPermissions.GetJobLabel(jobName)
	if not jobName then
		return nil
	end

	if not jobLabels then
		jobLabels = {}

		for name, job in pairs(TbFramework.GetJobs()) do
			jobLabels[name] = job.label
		end
	end

	return jobLabels[jobName] or jobName
end

--- Every business the player can see: their job's plus every explicit
--- membership, never a duplicate account id.
---@param source integer
---@return TbBusinessSummary[]
function TbSocietyPermissions.ListBusinessesForPlayer(source)
	local identifier = TbFramework.GetIdentifier(source)

	if not identifier then
		return {}
	end

	local businesses = {}
	local seen = {}

	local function add(account, role)
		local capabilities = TbSocietyPermissions.RoleToCapabilities(role)

		if seen[account.id] or not capabilities.view then
			return
		end

		seen[account.id] = true
		businesses[#businesses + 1] = {
			accountId = account.id,
			name = account.name,
			number = account.number,
			jobName = account.jobName,
			jobLabel = TbSocietyPermissions.GetJobLabel(account.jobName),
			role = role,
			capabilities = capabilities,
		}
	end

	local jobAccount, jobRole = TbSocietyPermissions.GetJobBusiness(source)

	if jobAccount then
		add(jobAccount, jobRole)
	end

	local ok, rows = TbDb.SelectMany(
		[[SELECT m.role, a.* FROM tb_account_members m
			JOIN tb_accounts a ON a.id = m.account_id
			WHERE m.identifier = ? AND a.type = 'society' AND a.deleted_at IS NULL
			ORDER BY a.name ASC]],
		{ identifier }
	)

	if ok then
		for _, row in ipairs(rows) do
			add(TbAccounts.RowToAccount(row), row.role)
		end
	end

	return businesses
end

--- Explicit staff of a business (not job-holders, those are implicit).
---@param accountId integer
---@return { identifier: string, role: TbRole, cardDailyLimit: integer? }[]
function TbSocietyPermissions.ListMembers(accountId)
	local ok, rows = TbDb.SelectMany('SELECT * FROM tb_account_members WHERE account_id = ? ORDER BY created_at ASC', { accountId })

	if not ok then
		return {}
	end

	-- One pass over the player list rather than a lookup per member.
	local onlineByIdentifier = {}
	for _, player in ipairs(TbFramework.GetPlayers()) do
		onlineByIdentifier[player.identifier] = player.source
	end

	local members = {}

	for i, row in ipairs(rows) do
		members[i] = {
			identifier = row.identifier,
			name = row.display_name,
			-- Their CURRENT server id when they happen to be connected. That
			-- is the number a manager can act on in game; the identifier is
			-- kept only as the stable key the callbacks address them by, and
			-- is never put in front of a player.
			serverId = onlineByIdentifier[row.identifier],
			role = row.role,
			cardDailyLimit = row.card_daily_limit,
		}
	end

	return members
end

--- Adds or updates a staff member.
---@param accountId integer
---@param identifier string
---@param role TbRole
---@param addedBy string?
---@return boolean ok
function TbSocietyPermissions.AddMember(accountId, identifier, role, addedBy, displayName)
	if not Config.Society.RoleCapabilities[role] then
		return false
	end

	-- COALESCE on update: a later role change passes no name (the member may
	-- be offline), and that must not wipe the one captured when they joined.
	return TbDb.Update(
		[[INSERT INTO tb_account_members (account_id, identifier, role, display_name, added_by) VALUES (?, ?, ?, ?, ?)
			ON DUPLICATE KEY UPDATE role = VALUES(role), display_name = COALESCE(VALUES(display_name), display_name)]],
		{ accountId, identifier, role, displayName, addedBy }
	)
end

---@param accountId integer
---@param identifier string
---@return boolean ok
function TbSocietyPermissions.RemoveMember(accountId, identifier)
	return TbDb.Update('DELETE FROM tb_account_members WHERE account_id = ? AND identifier = ?', { accountId, identifier })
end

--- Sets (or clears, with nil) a staff member's company-card daily limit.
---@param accountId integer
---@param identifier string
---@param limit integer?
---@return boolean ok
function TbSocietyPermissions.SetMemberCardLimit(accountId, identifier, limit)
	local ok, affected = TbDb.Update(
		'UPDATE tb_account_members SET card_daily_limit = ? WHERE account_id = ? AND identifier = ?',
		{ limit, accountId, identifier }
	)

	return ok and affected > 0
end

--- Daily ATM cap for a holder's company card on a business, their explicit
--- staff limit if set, else the config default. Job-holders without a staff
--- row get the default too.
---@param identifier string
---@param accountId integer
---@return integer
function TbSocietyPermissions.GetCardDailyLimit(identifier, accountId)
	local row = TbSocietyPermissions.GetMemberRow(identifier, accountId)

	if row and row.card_daily_limit then
		return row.card_daily_limit
	end

	return Config.Cards.DefaultStaffDailyLimit
end
