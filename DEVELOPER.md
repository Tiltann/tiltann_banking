# Developer guide

For people who change or extend tiltann_banking. Installing and configuring it is in [README.md](README.md), the exports for other scripts are in [exports.md](exports.md).

> **Note:** the money logic lives on the server. The client and the UI only ask, they never decide balances, limits or permissions. Keep it that way when you extend something: add the check in the server callback, not in the UI.

## Project layout

| Path | What is in it |
| --- | --- |
| `fxmanifest.lua` | Load order. `version` and `repository` are read by the update check. |
| `config/config.lua` | The only file server owners edit. Missing keys fall back to `shared/defaults.lua`. |
| `shared/` | Code for both sides: enums, helpers, logger, `TbSafe`, framework layer. |
| `server/` | Accounts, cards, ATM, billing, loans, tax, standing orders, society, terminal callbacks, exports, updater, database. |
| `client/` | Interaction (target, markers, help text), ATM and terminal peds, blips, NUI bridge, exports. |
| `web/` | The React UI. `web/dist` is built and committed. |
| `locales/` | Game text (`en.json`, `de.json`) and UI text (`locales/ui/`). |

Errors in callbacks and threads go through `TbSafe` (`shared/safe.lua`), so a failing handler logs an error instead of killing the resource.

## Inventory

### Adding another inventory

1. Copy `server/inventory/providers/ox_inventory.lua` to a new file.
2. Implement `AddItem(source, itemName, metadata)` (returns ok and the item serial), `GetItemBySerial(source, itemName, serial)` (returns the metadata or nil), `SetMetadata(source, itemName, serial, metadata)` and `RemoveItem(source, itemName, serial)`.
3. Register it at the bottom with `TbInventoryProvider.Register(Provider)`. Guard the top of the file so it only loads when `Config.Inventory` is your name and the resource is started.
4. Add the file to `server_scripts` in `fxmanifest.lua`, after `server/inventory/provider.lua`.
5. Set `Config.Inventory` to your name.

The inventory needs to support per item metadata with a unique serial for this to work as a physical card. If it cannot, use `'none'`.

## Framework layer

Nothing outside `shared/framework/` talks to ESX directly. `framework.lua` holds the `TbFramework` table. It picks an implementation on first use: if `Config.Framework` is `'auto'`, it checks for `qbx_core`, then `qb-core`, then `es_extended`, and takes the first one that is registered and present. Any other value is used as the implementation name. If nothing matches, it throws an error.

There are three implementations: `esx.lua` (the supported one), and `qb.lua` and `qbox.lua`. The last two are unfinished and have never been run on a server. When one of them is selected the server console prints a warning that it is not recommended. They have no society money mirror yet. `qbox.lua` is a thin file on top of `qb.lua`, since both frameworks use the same player data.

A framework file must implement these (all server side unless noted):

| Function | Meaning |
| --- | --- |
| `Ready()` | Shared. Block until the framework can be used. |
| `GetIdentifier(source)` | Persistent player id, nil if not logged in. |
| `GetName(source)` | Character name or nil. |
| `GetJob(source)` | `{ name, label, grade }` or nil. Grade is a number. |
| `GetCash(source)` | Cash on hand or nil. |
| `AddCash(source, amount)` | Returns true on success. |
| `RemoveCash(source, amount)` | Returns false if the player does not have enough. |
| `GetPlayers()` | List of `{ source, identifier }` for all online players. |
| `GetSourceByIdentifier(identifier)` | Source or nil if offline. |
| `GetJobs()` | Map of job name to `{ label, grades = { { grade, label } } }`. |
| `BankTarget` | A string used as the label in `tb_sync_log` (ESX uses `'esx_bank'`). |
| `GetBank(source)` | The framework bank balance or nil. |
| `SetBank(source, amount)` | Returns true on success. |
| `SetBankOffline(identifier, amount)` | Same for an offline player, usually a DB update. |
| `GetSocietyTargets()` | List of `{ name, get(job), set(job, amount) }` for society money kept by other resources. `get` may be missing if it cannot be read. Return only running ones. Empty list is fine. |
| `OnBankChanged(cb)` | Client side. Call `cb()` whenever the framework changes the player's bank. |

The file ends with `TbFramework.Register('name', Impl)`. On the client it registers early and returns, since only `Ready` and `OnBankChanged` are needed there (see the top of `esx.lua`).

### Adding another framework

1. Copy `shared/framework/esx.lua` to a new file and replace the ESX calls with the new framework's. `qb.lua` is a second example.
2. Register it at the bottom with `TbFramework.Register('name', Impl)`. If it is not finished, set `Impl.Experimental = true` and the server prints the not-recommended warning.
3. Add the file to `shared_scripts` in `fxmanifest.lua`, after `esx.lua`, and add its resource name to the auto detect list at the top of `framework.lua`.
4. Test with `Config.Framework = 'name'`.

For QBCore and Qbox the mapping is already written in `qb.lua`: identifier is `PlayerData.citizenid`, the name comes from `charinfo`, cash and bank from `PlayerData.money` and `Player.Functions.AddMoney/RemoveMoney/SetMoney`, the client change event is `QBCore:Client:OnMoneyChange`, the offline bank is the `money` JSON column of the `players` table.


## Balance mirror and live updates

The default personal account is mirrored into the framework bank balance, and job businesses are mirrored into society accounts (esx_addonaccount, esx_society) when those run. Our own tables are the source of truth. After every balance change the resource pushes the new value out. Other accounts (extra, savings, standalone businesses) are never mirrored.

When another script changes the framework bank, the framework fires its event (for ESX that is `esx:setAccountMoney` for `bank`). The client forwards a bare "something changed" to the server, the server re-reads the real balance itself and the open UI refreshes. The client never sends a balance. Society accounts and offline players cannot raise an event, so those are caught by a poll every `Bridge.PollIntervalMs`.

Any difference from outside is booked as a `sync_correction` transaction, so an external add or remove shows up as the difference in the history. `/tb_setbalance` sets an exact value and clears the transaction history of that account first, because the old history would no longer add up.


## Log levels

* `TbLogger.Debug` only prints while `Config.Logs.Debug` is on (`/tb_debug`). Use it for anything that happens often, for example every money movement or export call.
* `TbLogger.Warn` and `TbLogger.Error` always print.
* Start-up shows only short messages (`Database READY!`, `Started vX`) and the version check block, written with `print`.

## Update check

`server/updater/updater.lua` runs once on every start. It reads `version` from `fxmanifest.lua` on the configured branch (`raw.githubusercontent.com`), the section of `CHANGELOG.md` with the same version and the date of the last commit to the manifest. No GitHub releases are used. To publish an update raise `version`, add a `## <version>` section to `CHANGELOG.md` and push.

## Building the UI

The UI lives in `web/`: Vite, React, TypeScript and Tailwind CSS v4 (through `@tailwindcss/vite`). The built files in `web/dist` are committed, so you only need this if you change the UI.

```
cd web
npm install
npm run dev     # browser preview with fixture data
npm run build   # writes web/dist
```

Commit `dist/` together with any change in `src/`. More in `web/README.md`.

---

This resource was created with the help of generative AI.
