--- @module server.updater.updater
--- Checks the GitHub repository for a newer version of this resource and reports
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

--- GET with a User-Agent GitHub accepts. `callback(status, body)`.
---@param url string
---@param accept string?
---@param callback fun(status: integer, body: string)
local function Get(url, accept, callback)
	PerformHttpRequest(url, function(status, body)
		TbSafe.Run('updater:response', callback, status or 0, body or '')
	end, 'GET', '', {
		['User-Agent'] = ('tiltann_banking/%s'):format(TbUpdater.GetCurrentVersion()),
		['Accept'] = accept or '*/*',
	})
end

--- The `## <version>` section of CHANGELOG.md, without its heading.
---@param changelog string
---@param version string
---@return string
local function ChangelogSection(changelog, version)
	local text = changelog:gsub('\r', '')
	local out, inside = {}, false

	for line in (text .. '\n'):gmatch('(.-)\n') do
		local heading = line:match('^##%s+v?([%w%.%-]+)')

		if heading then
			if inside then
				break
			end

			inside = heading == version
		elseif inside then
			out[#out + 1] = line
		end
	end

	return (table.concat(out, '\n'):gsub('^%s+', ''):gsub('%s+$', ''))
end

--- Reads the newest version straight from the repository, no GitHub release
--- needed: the `version` in fxmanifest.lua on the branch is the latest
--- version, CHANGELOG.md has what changed, and the date of the last commit
--- to the manifest is when it came out. Async, the result arrives through
--- `callback`. Its third argument marks "nothing to compare against" (repo
--- not found / private) as opposed to a real failure.
---@param callback fun(release: TbReleaseInfo?, errorMessage: string?, isBenign: boolean?)
function TbUpdater.FetchLatestRelease(callback)
	local repository = TbUpdater.GetRepository()

	if not repository then
		callback(nil, 'no repository configured, set Config.Updater.Repository or fxmanifest\'s `repository`')
		return
	end

	local branch = Config.Updater.Branch or 'main'
	local raw = ('https://raw.githubusercontent.com/%s/%s/'):format(repository, branch)

	Get(raw .. 'fxmanifest.lua', nil, function(status, manifest)
		if status == 404 then
			callback(nil, ('repository %s (branch %s) not found or not public'):format(repository, branch), true)
			return
		end

		if status ~= 200 then
			callback(nil, ('GitHub returned HTTP %s for %s'):format(tostring(status), repository))
			return
		end

		local version = manifest:match("\nversion%s+['\"]([^'\"]+)['\"]") or manifest:match("^version%s+['\"]([^'\"]+)['\"]")

		if not version then
			callback(nil, 'no version found in the repository\'s fxmanifest.lua')
			return
		end

		local release = {
			version = version,
			name = ('v%s'):format(version),
			notes = '',
			url = ('https://github.com/%s'):format(repository),
			download = ('https://github.com/%s/archive/refs/heads/%s.zip'):format(repository, branch),
		}

		-- Changelog and date are nice to have: a failure there never hides the version.
		Get(raw .. 'CHANGELOG.md', nil, function(logStatus, changelog)
			if logStatus == 200 then
				release.notes = ChangelogSection(changelog, version)
			end

			local commitsUrl = ('https://api.github.com/repos/%s/commits?path=fxmanifest.lua&sha=%s&per_page=1'):format(repository, branch)

			Get(commitsUrl, 'application/vnd.github+json', function(commitStatus, commits)
				if commitStatus == 200 then
					local ok, decoded = pcall(json.decode, commits)

					if ok and type(decoded) == 'table' and decoded[1] and decoded[1].commit and decoded[1].commit.committer then
						release.publishedAt = decoded[1].commit.committer.date
					end
				end

				callback(release, nil)
			end)
		end)
	end)
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

local PREFIX = '^3[tiltann_banking]^7'

--- "2026-10-16T12:30:00Z" -> "2026-10-16 12:30 UTC"
---@param stamp string?
---@return string
local function FormatDate(stamp)
	local date, time = tostring(stamp or ''):match('^(%d+-%d+-%d+)T(%d+:%d+)')
	return date and ('%s %s UTC'):format(date, time) or 'unknown'
end

--- One check: fetch, compare, print a status block to the console.
function TbUpdater.Check()
	local current = TbUpdater.GetCurrentVersion()

	TbUpdater.FetchLatestRelease(function(release, errorMessage, isBenign)
		if not release then
			print(('%s version check: running ^5%s^7'):format(PREFIX, current))

			if isBenign then
				print(('%s repository not found or not public, nothing to compare against'):format(PREFIX))
				TbLogger.Debug('updater', 'nothing to compare against', { reason = errorMessage })
			else
				print(('%s ^1version check failed:^7 %s'):format(PREFIX, errorMessage or 'unknown error'))
				TbLogger.Warn('updater', 'update check failed', { error = errorMessage })
			end

			return
		end

		local newer = TbUpdater.IsNewer(release.version, current)

		print(('%s ------------------------------------------------'):format(PREFIX))
		print(('%s version checker is active (%s)'):format(PREFIX, TbUpdater.GetRepository() or '?'))
		print(('%s installed: ^5%s^7'):format(PREFIX, current))
		print(('%s latest:    ^5%s^7, updated %s'):format(PREFIX, release.version, FormatDate(release.publishedAt)))

		if newer then
			print(('%s ^3update available: %s -> %s^7'):format(PREFIX, current, release.version))
		else
			print(('%s ^2you are up to date^7'):format(PREFIX))
		end

		if release.notes ~= '' then
			print(('%s %s:\n  %s'):format(PREFIX, newer and "what's new" or 'last update', FormatNotes(release.notes)))
		end

		if newer then
			print(('%s get it: %s (Code -> Download ZIP)'):format(PREFIX, release.url))

			if release.download then
				print(('%s direct zip: %s'):format(PREFIX, release.download))
			end
		end

		print(('%s ------------------------------------------------'):format(PREFIX))

		if not newer then
			pendingUpdate = nil
			TbLogger.Debug('updater', 'up to date', { version = current })
			return
		end

		pendingUpdate = release

		TbLogger.Debug('updater', 'update available', {
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

--- Starts the update check. The check runs immediately, once per resource
--- start or restart.
function TbUpdater.Start()
	if checkStarted or not Config.Updater.Enabled then
		return
	end

	checkStarted = true

	TbSafe.Run('updater:check', TbUpdater.Check)

end
