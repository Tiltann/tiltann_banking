# tiltann_banking

A banking resource for FiveM. Players get personal and savings accounts, businesses tied to jobs, bank cards with a PIN, ATMs, a tablet style bank terminal at the counters, loans, tax, invoices and standing orders. The UI is a React page (see `web/`).

Requirements:

* ox_lib
* oxmysql
* A framework. ESX is implemented and the only one that is supported. QBCore and Qbox files exist but are untested and print a warning when used, see "Framework layer".
* ox_inventory (optional, for physical bank cards)
* ox_target (optional, otherwise a help text and the E key are used)

## Install

1. Put the folder into your resources and keep the name `tiltann_banking`.
2. Start it after its dependencies and your framework:

```
ensure ox_lib
ensure oxmysql
ensure es_extended
ensure ox_inventory
ensure ox_target
ensure tiltann_banking
```

3. Admins: anyone in the framework group `Config.Admin.Group` (default `admin`) can use the commands. You can also give the ace `add_ace group.admin tiltann_banking.admin allow`, but it is not required.

4. Add the card item to ox_inventory if you use it (see "Inventory").

The database is installed by the resource itself. On start it checks for its tables and creates them (schema in `server/database/schema.lua`) if they are missing, then applies migrations. You do not import anything by hand.

## Config

`config/config.lua` is the only file you should edit. Anything you leave out falls back to `shared/defaults.lua`, so you can also copy any key from that file into your config to override it. Tables are merged, lists are replaced.

The bank counters (`Bank.Zones`), blips and clerk peds (`Bank.Peds`) use the usual bank locations.

| Option | What it does |
| --- | --- |
| `Framework` | `'auto'` (default), `'esx'`, `'qb'` or `'qbox'`. qb and qbox are untested. |
| `Language` | `'en'` or `'de'`. Files are in `locales/`. |
| `Inventory` | `'ox_inventory'` or `'none'`. |
| `Interaction.Mode` | `'target'` (ox_target), `'helpnotification'` (help text plus key), `'auto'` (ox_target if running, else help text). `Interaction.Key` defaults to 38 (E). `Interaction.HelpText = true` forces the corner help text and the key on top of ox_target. `'custom'` sets up nothing and calls `Interaction.Custom(openAtm, openBank, openBilling)` once, put your own code there. `Atm.PropModels` is the list of ATM props that target, help text and custom mode use. |
| `Bank.Zones` | Counter positions: `coords`, `heading`, `size` (width, length, height of the target box), `label`. |
| `Bank.Blips` | Map blips. `Locations` lists one blip per bank, each can set its own `sprite`, `colour`, `scale` and `label`. `Bank.AtmBlips` does the same for ATMs (off by default). |
| `Bank.Peds` | Clerk peds: `coords` (vector4), `model`, `scenario`. |
| `Bank.SpawnPeds` | Spawn the clerks or not. |
| `Bank.Blips` | `true`/`false`, or a table with Label, Sprite, Colour, Scale. |
| `Atm` | `Locations` for extra ATMs, `PropModels`, `QuickWithdraw` amounts, `PinLockoutAttempts`. ATM props on the map are used by default. |
| `Accounts` | `Max` accounts per player, `NewAccountPrice`, `StartBalance`: `First` is the money on a first account, set it to `false` if your framework already gives starting money (the account then takes over the framework bank balance), `Other` is for later accounts. |
| `Limits` | `MinTransactionAmount`, `MaxTransactionAmount`, `DailyWithdrawMax`. |
| `Cards`, `Savings`, `Loans`, `Tax`, `Billing`, `StandingOrders` | Each has `Enabled` plus its own settings (rates, limits, intervals). Tax is off by default. |
| `Cards.AllowWeakPins` | `false` by default: PINs like 1111, 1234, 4321, 1212 or 2580 are refused. Set `true` to allow them. `Cards.MaxPerAccount` limits cards per account. |
| `Society` | Role capabilities and the default role for job grades. |
| `Logs.Webhook` | One Discord webhook for everything. Each category shows with its own icon and colour, players appear as name and server id. `Logs.SecurityWebhook` is an optional second channel for security alerts and large amounts (`Logs.LargeTransactionThreshold`). `Logs.WebhookURLs` can still route single categories, `Logs.Enabled` switches categories off. Embeds are batched so Discord never throttles a burst. |
| `Logs.Debug` | Verbose console logging. Can be toggled with `/tb_debug`. `Logs.Console.Ledger = true` also prints every money movement. A warning that repeats is printed once a minute with a count. |
| `UI` | `CurrencySymbol` and `Colors`. |
| `Bridge`, `Updater`, `Database` | Poll interval for external balance changes, GitHub update check, column migration and schema checks. |

## Inventory

### With ox_inventory

The card item is `mastercard` (`Config.Cards.ItemName`). ox_inventory already ships this item, so there is nothing to add. If you removed it, put it back in `ox_inventory/data/items.lua`:

```lua
['mastercard'] = {
	label = 'Bank Card',
	weight = 10,
	stack = false,
	close = true,
	description = 'A bank card. Use it at an ATM.',
},
```

To use a different item, change `Config.Cards.ItemName` and add that item the same way. Cards that were already issued under the old name `tb_bankcard` are not recognised anymore, issue new ones.

1. Make sure the item exists and has `stack = false`, every card has to be its own item.
2. Restart ox_inventory, then `restart tiltann_banking`. Start ox_inventory before this resource.
3. Test it: open the terminal, go to Cards, request a card. The item shows up in your inventory. Do not add it with `/giveitem`, a card needs its database row to be usable.

You do not set any metadata yourself. The resource stamps its own `metadata.serial` and `cardNumber` when it issues a card, and uses the serial to find that exact item again later. `stack = false` matters, every card has to be its own item.

### Without an inventory, or without metadata support

Set `Config.Inventory = 'none'`. Cards then live only in the `tb_cards` table and no item is ever given. The ATM and the terminal authorise from the database, and the PIN hash is stored in `tb_cards`. Everything still works, players just do not see a physical item in their bag.

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

## How it works

**Accounts.** Every player gets a default personal account on first use, plus extra accounts up to `Accounts.Max`. Each has an account number. Money moves between accounts by number. Transactions are written to `tb_transactions` and every debit is guarded against negative balances.

**Businesses and roles.** A job gets a business account. Job grades map to roles: contributor, admin or owner (the top grade is always owner). Roles decide who can view, deposit, withdraw, manage staff, invoice or delete. Change a grade with `/tb_setgraderole`. Standalone businesses exist too and are not linked to a job.

**Cards, ATM and PIN.** A player orders a card for an account and sets a PIN (length from `Cards.MinPinLength` to `MaxPinLength`, common PINs are denied). The PIN is stored as a hash. The ATM asks for the card and PIN, too many wrong tries lock the card (`Atm.PinLockoutAttempts`) and it can be unlocked in the terminal. Lost cards can be replaced for `Cards.ReplacementFee`. Company cards can carry a daily limit per staff member.

**Terminal.** Clerk peds at `Bank.Zones` open a tablet with a Personal tab and a Business tab: dashboard, accounts, transfers, history and the feature panels below.

**Loans.** Fixed presets or custom amounts between the min and max. Interest is applied once to the principal and the total is split into installments. Missed installments are counted against `Loans.MaxMissedPayments`.

**Tax.** Off by default. Flat or bracket mode, applied on deposits, withdrawals or transfers as configured. The tax goes to a job's business, a given account number, or is burned.

**Billing.** Players and businesses send invoices to an account number or a player. The receiver pays from the UI. Overdue invoices are swept on a timer, optionally charged automatically.

**Standing orders.** Recurring transfers with an interval. After `MaxFailedRuns` failures in a row an order switches itself off.

**Savings.** Extra savings accounts pay interest on a timer. Withdrawals are locked for `WithdrawLockSeconds` after a deposit.

### Balance mirror and live updates

The default personal account is mirrored into the framework bank balance, and job businesses are mirrored into society accounts (esx_addonaccount, esx_society) when those run. Our own tables are the source of truth. After every balance change the resource pushes the new value out. Other accounts (extra, savings, standalone businesses) are never mirrored.

When another script changes the framework bank, the framework fires its event (for ESX that is `esx:setAccountMoney` for `bank`). The client forwards a bare "something changed" to the server, the server re-reads the real balance itself and the open UI refreshes. The client never sends a balance. Society accounts and offline players cannot raise an event, so those are caught by a poll every `Bridge.PollIntervalMs`.

Any difference from outside is booked as a `sync_correction` transaction, so an external add or remove shows up as the difference in the history. `/tb_setbalance` sets an exact value and clears the transaction history of that account first, because the old history would no longer add up.

## Commands

All commands need the framework group from `Config.Admin.Group`, the `tiltann_banking.admin` ace, or the server console.

| Command | Use |
| --- | --- |
| `/tb_setbalance [id] [amount]` | Set the default account of an online player. Clears that account's history. |
| `/tb_setsociety [job] [amount]` | Set a job business balance. Clears that account's history. |
| `/tb_setgraderole [job] [grade] [owner\|admin\|contributor]` | Set the business role for a job grade. |
| `/tb_debug [on\|off]` | Toggle debug logging. No argument flips it. |

The resource checks GitHub for a newer release (`Updater` in the config) and reports it in the console.

## Exports

Defined in `server/exports.lua` and `client/exports.lua`. Server exports are wrapped, so a bad argument returns false or nil and logs an error instead of throwing.

### Server

Wherever a recipient is asked for, you can give either an account number (`920-48271039`) or a server id. A server id means that player's main account, so the player has to be online.

```lua
exports.tiltann_banking:GetBalance(identifier)                       -- integer
exports.tiltann_banking:GetDefaultAccount(identifier)                -- account table
exports.tiltann_banking:AddMoney(identifier, amount, note)           -- boolean
exports.tiltann_banking:RemoveMoney(identifier, amount, note)        -- false if not enough
exports.tiltann_banking:GetBalanceBySource(source)                   -- same three, by server id
exports.tiltann_banking:AddMoneyBySource(source, amount, note)
exports.tiltann_banking:RemoveMoneyBySource(source, amount, note)
exports.tiltann_banking:TransferToNumber(fromIdentifier, numberOrServerId, amount, note) -- ok, reason
exports.tiltann_banking:GetAccountByNumber(number)                   -- account or nil
exports.tiltann_banking:GetSocietyBalance(job)                       -- integer
exports.tiltann_banking:AddSocietyMoney(job, amount, note)           -- boolean
exports.tiltann_banking:RemoveSocietyMoney(job, amount, note)        -- boolean
exports.tiltann_banking:CreateInvoice(fromAccountId, numberOrServerId, amount, reason) -- ok, reason
```

`CreateInvoice` needs `Config.Billing.Enabled`.

### Client

```lua
exports.tiltann_banking:OpenBank()     -- bank terminal
exports.tiltann_banking:OpenAtm()      -- ATM screen
exports.tiltann_banking:OpenBilling()  -- billing menu (F7 by default)
exports.tiltann_banking:CloseUi()
exports.tiltann_banking:IsUiOpen()     -- boolean
exports.tiltann_banking:RefreshUi()    -- reload the data of the open screen
```

## Billing menu

Press F7 (`Config.Billing.Key`, players can rebind it in the GTA key settings) or call `OpenBilling()`. Pick where the bill comes from: one of your own accounts, or a business where your role is allowed to invoice. Enter a server id or an account number, an amount and a reason. When the bill is paid, the money goes to the account it was sent from, so a bill from a business pays the business. The same menu lists the bills you received so you can pay or decline them.

## Building the UI

The UI lives in `web/`: Vite, React, TypeScript and Tailwind CSS v4 (through `@tailwindcss/vite`). The built files in `web/dist` are committed, so you only need this if you change the UI.

```
cd web
npm install
npm run dev     # browser preview with fixture data
npm run build   # writes web/dist
```

Commit `dist/` together with any change in `src/`. More in `web/README.md`.
