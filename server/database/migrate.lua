--- @module server.database.migrate
--- Schema bootstrap. Waits for oxmysql to connect (MySQL.ready), asks the
--- database which of this resource's tables already exist, and installs
--- server/database/schema.lua only when something is missing, so a running server
--- pays for one information_schema lookup per start instead of replaying
--- every CREATE TABLE. Columns that later versions added to existing tables
--- are handled separately, since `CREATE TABLE IF NOT EXISTS` never touches
--- a table that is already there.
---
--- Everything that queries money waits on TbMigrate.OnReady, so a server
--- with no schema (or an owner who installs the SQL by hand) gets one clear
--- error instead of every tick failing in a loop. See config.database.lua.

TbMigrate = {}

local schemaReady = false
local readyCallbacks = {}

--- Runs `callback` once the schema is confirmed usable. Called immediately
--- if that already happened. Never fires when the schema is incomplete and
--- Config.Database.HaltOnIncompleteSchema is on, that is the point.
---@param callback function
function TbMigrate.OnReady(callback)
	if schemaReady then
		callback()
		return
	end

	readyCallbacks[#readyCallbacks + 1] = callback
end

---@return boolean
function TbMigrate.IsReady()
	return schemaReady
end

local function MarkReady()
	schemaReady = true

	for _, callback in ipairs(readyCallbacks) do
		TbSafe.Run('migrate:onReady', callback)
	end

	readyCallbacks = {}
end

--- Splits the schema into individual statements.
---
--- Comments are stripped BEFORE splitting: `--` comment text may contain a
--- semicolon ("Several per player; exactly one has ..."), which would
--- otherwise cut a statement in half and send prose to the database. The
--- file is controlled by this resource and contains no stored procedures or
--- triggers with embedded semicolons, and no string literal contains `--`,
--- so line-comment stripping plus a split on `;` is sufficient, documented
--- here so a future contributor adding either knows to revisit this first.
---@param sql string
---@return string[] statements
local function SplitStatements(sql)
	local stripped = {}

	for line in (sql .. '\n'):gmatch('([^\n]*)\n') do
		stripped[#stripped + 1] = line:gsub('%-%-.*$', '')
	end

	local statements = {}

	for statement in table.concat(stripped, '\n'):gmatch('[^;]+') do
		local trimmed = statement:gsub('^%s+', ''):gsub('%s+$', '')

		if trimmed ~= '' then
			statements[#statements + 1] = trimmed
		end
	end

	return statements
end

--- The tables this resource needs, read out of the schema itself rather
--- than duplicated in a config list that could drift out of sync with it.
---@param sql string
---@return string[] tableNames
local function TablesInSchema(sql)
	local names = {}

	for name in sql:gmatch('CREATE TABLE IF NOT EXISTS%s+`([%w_]+)`') do
		names[#names + 1] = name
	end

	return names
end

--- Which of `tableNames` are absent from the current database.
---@param tableNames string[]
---@return string[]? missing nil when the check itself failed.
local function FindMissingTables(tableNames)
	if #tableNames == 0 then
		return {}
	end

	local placeholders = string.rep('?', #tableNames, ', ')
	local ok, rows = TbDb.SelectMany(
		('SELECT TABLE_NAME AS name FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN (%s)'):format(placeholders),
		tableNames
	)

	if not ok then
		return nil
	end

	local present = {}

	for _, row in ipairs(rows) do
		present[row.name] = true
	end

	local missing = {}

	for _, name in ipairs(tableNames) do
		if not present[name] then
			missing[#missing + 1] = name
		end
	end

	return missing
end

--- Executes every statement of the schema. Each one is
--- `CREATE TABLE IF NOT EXISTS`, so this is safe to repeat; a single failing
--- statement is logged but does not abort the rest, so one bad table never
--- costs you the other ten.
---@param sql string
---@return integer failures
local function RunInstall(sql)
	local statements = SplitStatements(sql)
	local failures = 0

	for _, statement in ipairs(statements) do
		if not TbDb.SafeQuery(MySQL.query.await, statement) then
			failures = failures + 1
		end
	end

	TbLogger.Debug('migrate', 'ran schema install', { statements = #statements, failures = failures })

	return failures
end

--- Adds a column to an existing table if it's missing. Checked via
--- information_schema instead of `ADD COLUMN IF NOT EXISTS`, which MySQL
--- (unlike MariaDB) does not support.
---@param tableName string
---@param columnName string
---@param definition string e.g. 'TIMESTAMP NULL DEFAULT NULL AFTER `last_interest_at`'
---@return boolean added
function TbMigrate.EnsureColumn(tableName, columnName, definition)
	local ok, row = TbDb.SelectOne(
		'SELECT COUNT(*) AS n FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
		{ tableName, columnName }
	)

	if not ok or not row or (row.n or 0) > 0 then
		return false
	end

	if not TbDb.SafeQuery(MySQL.query.await, ('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tableName, columnName, definition)) then
		return false
	end

	TbLogger.Debug('migrate', 'added column', { table = tableName, column = columnName })
	return true
end

--- Columns introduced after 1.0.0, keep in sync with server/database/schema.lua.
--- Existing installs get them here; fresh ones already have them from the
--- CREATE TABLE above.
local function EnsureNewColumns()
	local added = 0

	for _, column in ipairs({
		{ 'tb_accounts', 'locked_until', 'TIMESTAMP NULL DEFAULT NULL AFTER `last_interest_at`' },
		{ 'tb_accounts', 'history_cleared_at', 'TIMESTAMP NULL DEFAULT NULL AFTER `locked_until`' },
		{ 'tb_tax_records', 'kind', "VARCHAR(16) NOT NULL DEFAULT 'deposit' AFTER `treasury_account_id`" },
		{ 'tb_account_members', 'display_name', 'VARCHAR(100) DEFAULT NULL AFTER `role`' },
		{ 'tb_invoices', 'share_percent', 'TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER `created_by`' },
		{ 'tb_invoices', 'share_account_id', 'INT UNSIGNED DEFAULT NULL AFTER `share_percent`' },
		{ 'tb_loans', 'closed_at', 'TIMESTAMP NULL DEFAULT NULL AFTER `status`' },
	}) do
		if TbMigrate.EnsureColumn(column[1], column[2], column[3]) then
			added = added + 1
		end
	end

	if added > 0 then
		TbLogger.Debug('migrate', 'schema migrated', { columns_added = added })
	end
end

--- The whole bootstrap, once the database is connected.
local function Bootstrap()
	local sql = TbSchema

	local required = TablesInSchema(sql)
	local missing = FindMissingTables(required)

	if not missing then
		TbLogger.Error('migrate', 'could not read the table list from the database, check the oxmysql connection string and that the user may read information_schema')
		return
	end

	if #missing == 0 then
		TbLogger.Debug('migrate', 'schema present', { tables = #required })
	else
		TbLogger.Debug('migrate', 'installing schema, tables are missing', { missing = missing })

		RunInstall(sql)

		local stillMissing = FindMissingTables(required)

		if stillMissing == nil or #stillMissing > 0 then
			TbLogger.Error('migrate', 'schema install did not create every table, the database user most likely lacks CREATE permission', {
				missing = stillMissing or 'unknown',
			})

			if Config.Database.HaltOnIncompleteSchema then
				return
			end
		else
			TbLogger.Debug('migrate', 'schema installed', { tables = #required })
		end
	end

	if Config.Database.AutoMigrate then
		EnsureNewColumns()
	end

	MarkReady()
	print('^3[tiltann_banking]^7 ^2Database READY!^7')
end

--- Waits for oxmysql, then bootstraps. MySQL.ready runs its callback in its
--- own thread, so this never blocks the rest of the resource from loading.
CreateThread(function()
	local timedOut = true

	SetTimeout((Config.Database.ConnectTimeoutSeconds or 60) * 1000, function()
		if timedOut and not schemaReady then
			TbLogger.Error('migrate', ('the database did not connect within %d seconds, tiltann_banking is idle until oxmysql is up'):format(Config.Database.ConnectTimeoutSeconds or 60))
		end
	end)

	MySQL.ready(function()
		timedOut = false
		TbSafe.Run('migrate:bootstrap', Bootstrap)
	end)
end)
