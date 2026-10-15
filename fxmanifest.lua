fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tiltann_banking'
author 'tiltann'
description 'Banking for FiveM: personal and savings accounts, businesses, bank cards, ATM, loans, tax, invoices, standing orders and a tablet bank terminal.'

-- `version` and `repository` are read at runtime by server/updater/updater.lua:
-- it asks the GitHub API for the newest release of this repository and
-- reports the version, the release notes and the download link in the
-- console. Bump `version` on every release so the check stays meaningful.
version '1.0.0'
repository 'https://github.com/Tiltann/tiltann_banking'

shared_script '@ox_lib/init.lua'

ox_libs {
	'locale',
	'table',
}

shared_scripts {
	'shared/enums.lua',
	'shared/utils.lua',
	'shared/sha256.lua',
	'shared/framework/framework.lua',
	'shared/framework/esx.lua',
	'shared/framework/qb.lua',
	'shared/framework/qbox.lua',
	'shared/logger.lua',
	'shared/safe.lua',
	'config/config.lua',
	'shared/defaults.lua',
}

server_scripts {
	'@oxmysql/lib/MySQL.lua',
	'server/admin.lua',
	'server/database/schema.lua',
	'server/database/safe.lua',
	'server/database/migrate.lua',
	'server/logging/webhook.lua',
	'server/accounts/accounts.lua',
	'server/accounts/transactions.lua',
	'server/accounts/personal.lua',
	'server/accounts/savings.lua',
	'server/bridge/external_bridge.lua',
	'server/society/permissions.lua',
	'server/society/actions.lua',
	'server/society/members.lua',
	'server/inventory/provider.lua',
	'server/inventory/providers/ox_inventory.lua',
	'server/cards/cards.lua',
	'server/loans/loans.lua',
	'server/tax/tax.lua',
	'server/billing/billing.lua',
	'server/standing_orders/standing_orders.lua',
	'server/atm/atm.lua',
	'server/terminal/personal.lua',
	'server/terminal/business.lua',
	'server/updater/updater.lua',
	'server/exports.lua',
	'server/main.lua',
}

client_scripts {
	'client/main.lua',
	'client/ui/bank_ui.lua',
	'client/interact.lua',
	'client/blips.lua',
	'client/atm.lua',
	'client/terminal.lua',
	'client/exports.lua',
}

ui_page 'web/dist/index.html'

files {
	'web/dist/index.html',
	'web/dist/**/*',
	-- ox_lib's locale module reads these itself (LoadResourceFile), so they
	-- belong in `files`, never in shared_scripts.
	'locales/*.json',
	'locales/ui/*.json',
}

dependencies {
	'ox_lib',
	'oxmysql',
}

-- ox_target is a soft dependency: client/atm.lua and client/terminal.lua
-- check GetResourceState at runtime and fall back to a keybind-based
-- interact prompt if ox_target isn't present, so it's intentionally not
-- listed here.
