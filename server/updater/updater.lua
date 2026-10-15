--- @module server.updater.updater
--- Checks GitHub releases for a newer version of this resource and reports
--- it in the console (and to admins in-game). Deliberately REPORT-ONLY: it
--- never downloads or writes a file. A banking resource that overwrites its
--- own scripts while players hold balances is a data-loss incident waiting
--- to happen, so the decision to update stays with the server owner.
---
--- Everything it needs comes from fxmanifest.lua (`version`, `repository`)
--- and config/config.updater.lua.

TbUpdater = {}

---@class TbReleaseInfo
---@field version string Tag without a leading 'v'.
---@field name string Release title.
---@field notes string Release body (changelog).
---@field url string Release page link.
---@field download string? Link to the first uploaded asset, if any.
---@field publishedAt string?

--- Turns '1.2.10' into a comparable list of numbers. Non-numeric suffixes
--- ('-beta') are ignored for ordering but kept out of equality, so a
--- prerelease of the same numbers never counts as newer.
---@param version string
---@return integer[]
local function ParseVersion(version)
	local parts = {}

	for number in tostring(version):gmatch('%d+') do
		parts[#parts + 1] = tonumber(number)
	end

	return parts
end

--- True when `candidate` is a strictly higher version than `current`.
---@param candidate string
---@param current string
---@return boolean
function TbUpdater.IsNewer(candidate, current)
	local a, b = ParseVersion(candidate), ParseVersion(current)

	for i = 1, math.max(#a, #b) do
		local left, right = a[i] or 0, b[i] or 0

		if left ~= right then
			return left > right
		end
	end

	return false
end

--- 'https://github.com/owner/name' or 'owner/name' -> 'owner/name'.
---@param repository string?
---@return string?
local function NormalizeRepository(repository)
	if type(repository) ~= 'string' or repository == '' then
		return nil
	end

	local owner, name = repository:match('github%.com/([^/]+)/([^/%s]+)')

	if not owner then
		owner, name = repository:match('^([%w%-%._]+)/([%w%-%._]+)$')
	end

	if not owner or not name then
		return nil
	end

	return ('%s/%s'):format(owner, (name:gsub('%.git$', '')))
end

--- The repository to check: Config.Updater.Repository, else fxmanifest's
--- `repository` field.
---@return string?
function TbUpdater.GetRepository()
	return NormalizeRepository(Config.Updater.Repository)
		or NormalizeRepository(GetResourceMetadata(GetCurrentResourceName(), 'repository', 0))
end

---@return string
function TbUpdater.GetCurrentVersion()
	return GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '0.0.0'
end

--- Fetches the newest release from the GitHub API. Async (PerformHttpRequest
--- has no await form here), so the result arrives through `callback`. The
--- callback's third argument marks "nothing to compare against" (no release
--- published, private repo) as opposed to a real failure.
---@param callback fun(release: TbReleaseInfo?, errorMessage: string?, isBenign: boolean?)
function TbUpdater.FetchLatestRelease(callback)
	local repository = TbUpdater.GetRepository()

	if not repository then
		callback(nil, 'no repository configured, set Config.Updater.Repository or fxmanifest\'s `repository`')
		return
	end

	local url = ('https://api.github.com/repos/%s/releases/latest'):format(repository)

	PerformHttpRequest(url, function(status, body)
		TbSafe.Run('updater:response', function()
			if status == 404 then
				-- Private repository, wrong name, or simply no release published
				-- yet. A normal state for a fork or a WIP repo, so it is reported
				-- as "nothing to compare against" rather than as a failure.
				callback(nil, ('no published release found for %s'):format(repository), true)
				return
			end

			if status ~= 200 then
				callback(nil, ('GitHub API returned HTTP %s for %s'):format(tostring(status), repository))
				return
			end

			local parsed, decoded = pcall(json.decode, body or '')

			if not parsed or type(decoded) ~= 'table' or type(decoded.tag_name) ~= 'string' then
				callback(nil, 'GitHub API response could not be parsed')
				return
			end

			local download = nil

			if type(decoded.assets) == 'table' and decoded.assets[1] then
				download = decoded.assets[1].browser_download_url
			end

			callback({
				version = (decoded.tag_name:gsub('^[vV]', '')),
				name = decoded.name or decoded.tag_name,
				notes = type(decoded.body) == 'string' and decoded.body or '',
				url = decoded.html_url or ('https://github.com/%s/releases'):format(repository),
				download = download,
				publishedAt = decoded.published_at,
			}, nil)
		end)
	end, 'GET', '', {
		['User-Agent'] = ('tiltann_banking/%s'):format(TbUpdater.GetCurrentVersion()),
		['Accept'] = 'application/vnd.github+json',
	})
end

---@type TbReleaseInfo? Set once a newer release has been seen, for the admin notice.
local pendingUpdate = nil

--- The newest release seen so far, or nil when up to date.
---@return TbReleaseInfo?
function TbUpdater.GetPendingUpdate()
	return pendingUpdate
end

--- Trims release notes to Config.Updater.MaxNotesLength and indents them so
--- a multi-line changelog stays readable in the server console.
---@param notes string
---@return string
local function FormatNotes(notes)
	local text = notes:gsub('\r', '')

	if #text > Config.Updater.MaxNotesLength then
		text = text:sub(1, Config.Updater.MaxNotesLength) .. '\n  ... (see the release page for the rest)'
	end

	return (text:gsub('\n', '\n  '))
end

--- One check: fetch, compare, report.
function TbUpdater.Check()
	local current = TbUpdater.GetCurrentVersion()

	TbUpdater.FetchLatestRelease(function(release, errorMessage, isBenign)
		if not release then
			if isBenign then
				TbLogger.Debug('updater', 'nothing to compare against', { reason = errorMessage })
			else
				TbLogger.Warn('updater', 'update check failed', { error = errorMessage })
			end

			return
		end

		if not TbUpdater.IsNewer(release.version, current) then
			pendingUpdate = nil
			TbLogger.Info('updater', 'up to date', { version = current })
			return
		end

		pendingUpdate = release

		print(('^3[tiltann_banking]^7 ^5update available: %s -> %s^7'):format(current, release.version))
		print(('^3[tiltann_banking]^7 %s'):format(release.name))

		if release.notes ~= '' then
			print(('^3[tiltann_banking]^7 changes:\n  %s'):format(FormatNotes(release.notes)))
		end

		print(('^3[tiltann_banking]^7 release: %s'):format(release.url))

		if release.download then
			print(('^3[tiltann_banking]^7 download: %s'):format(release.download))
		end

		TbLogger.Info('updater', 'update available', {
			current = current,
			latest = release.version,
			url = release.url,
			published = release.publishedAt,
		})

		if TbLog then
			TbLog('admin_actions', 'Update available', {
				{ name = 'Installed', value = current },
				{ name = 'Latest', value = release.version },
				{ name = 'Release', value = release.url },
			}, Config.Logs.Colors.warning)
		end
	end)
end

--- /tb_version, prints the installed version and re-runs the check.
local lastManualCheck = 0

TbSafe.Command('tb_version', function(source)
	if not TbAdmin.Is(source) then
		return
	end

	local current = TbUpdater.GetCurrentVersion()
	local repository = TbUpdater.GetRepository() or 'not configured'
	local message = ('tiltann_banking %s (%s)'):format(current, repository)

	if source == 0 then
		print(('[tiltann_banking] %s'):format(message))
	else
		TriggerClientEvent('ox_lib:notify', source, { description = message })
	end

	-- At most one GitHub request every 30 seconds, however often it is typed.
	if Config.Updater.Enabled and GetGameTimer() - lastManualCheck > 30000 then
		lastManualCheck = GetGameTimer()
		TbUpdater.Check()
	end
end, false)

--- Tells a connecting admin about a pending update, once per join.
AddEventHandler('playerJoining', function()
	local source = source

	if not Config.Updater.Enabled or not Config.Updater.NotifyAdmins or not pendingUpdate then
		return
	end

	SetTimeout(20000, function()
		if pendingUpdate and TbAdmin.Is(source) then
			TriggerClientEvent('ox_lib:notify', source, {
				description = ('tiltann_banking %s is available (you run %s)'):format(pendingUpdate.version, TbUpdater.GetCurrentVersion()),
			})
		end
	end)
end)

local checkStarted = false

--- Starts the update check. First check runs shortly after boot (so it
--- never competes with the schema migration). Once per resource start.
function TbUpdater.Start()
	if checkStarted or not Config.Updater.Enabled then
		return
	end

	checkStarted = true

	SetTimeout(15000, function()
		TbSafe.Run('updater:check', TbUpdater.Check)
	end)

end
