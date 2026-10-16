# tiltann_banking

A banking resource for FiveM. Players get personal and savings accounts, businesses tied to jobs, bank cards with a PIN, ATMs, a tablet style bank terminal at the counters, loans, tax, invoices and standing orders. The UI is a React page (see `web/`).

## Preview:
https://streamable.com/u0ae9x

Exports for other scripts are described in [exports.md](exports.md). Changes are listed in [CHANGELOG.md](CHANGELOG.md).

Requirements:

* ox_lib
* oxmysql
* A framework. ESX is implemented and the only one that is supported. QBCore and Qbox files exist but are untested and print a warning when used, see the framework section in [DEVELOPER.md](DEVELOPER.md).
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
| `Interaction.Mode` | `'target'` (ox_target), `'helpnotification'` (help text plus key), `'auto'` (ox_target if running, else help text). `Interaction.Key` defaults to 38 (E). `Interaction.HelpText = true` forces the corner help text and the key on top of ox_target. `'custom'` sets up nothing and calls `Interaction.Custom(openAtm, openBank, openBilling)` once, put your own code there. `Atm.PropModels` is the list of ATM props that target, help text and custom mode use. Each bank counter has one target: the clerk ped where there is one, the box zone otherwise. Without ox_target, a marker and the help text show inside `Bank.TerminalInteractDistance` / `Atm.InteractDistance` (ox_lib zones). |
| `Bank.Zones` | Counter positions: `coords`, `heading`, `size` (width, length, height of the target box), `label`. |
| `Bank.Blips` | Map blips. `Locations` lists one blip per bank, each can set its own `sprite`, `colour`, `scale` and `label`. `Bank.AtmBlips` does the same for ATMs (off by default). |
| `Bank.Peds` | Clerk peds: `coords` (vector4), `model`, `scenario`. |
| `Bank.SpawnPeds` | Spawn the clerks or not. |
| `Atm` | `Locations` for extra ATMs, `PropModels`, `QuickWithdraw` amounts, `PinLockoutAttempts`. ATM props on the map are used by default. |
| `Accounts` | `Max` accounts per player, `NewAccountPrice`, `StartBalance`: `First` is the money on a first account, set it to `false` if your framework already gives starting money (the account then takes over the framework bank balance), `Other` is for later accounts. |
| `Limits` | `MinTransactionAmount`, `MaxTransactionAmount`, `DailyWithdrawMax`. |
| `Cards`, `Savings`, `Loans`, `Tax`, `Billing`, `StandingOrders` | Each has `Enabled` plus its own settings (rates, limits, intervals). Tax is off by default. |
| `Cards.AllowWeakPins` | `false` by default: PINs like 1111, 1234, 4321, 1212 or 2580 are refused. Set `true` to allow them. `Cards.MaxPerAccount` limits cards per account. |
| `Society` | Role capabilities and the default role for job grades. |
| `Logs.Webhook` | One Discord webhook for everything. Each category shows with its own icon and colour, players appear as name and server id. `Logs.SecurityWebhook` is an optional second channel for security alerts and large amounts (`Logs.LargeTransactionThreshold`). `Logs.WebhookURLs` can still route single categories, `Logs.Enabled` switches categories off. Embeds are batched so Discord never throttles a burst. |
| `Logs.Debug` | Verbose console logging, including every money movement and export call. Can be toggled with `/tb_debug`. Without it the console only shows start messages, warnings and errors. A warning that repeats is printed once a minute with a count. |
| `UI` | `CurrencySymbol` and `Colors`. |
| `Bridge`, `Updater`, `Database` | Poll interval for external balance changes, the update check (`Updater.Enabled`, `Repository`, `Branch`), column migration and schema checks. |

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

## How it works

**Accounts.** Every player gets a default personal account on first use, plus extra accounts up to `Accounts.Max`. Each has an account number. Money moves between accounts by number. Transactions are written to `tb_transactions` and every debit is guarded against negative balances.

**Businesses and roles.** A job gets a business account. Job grades map to roles: contributor, admin or owner (the top grade is always owner). Roles decide who can view, deposit, withdraw, manage staff, invoice or delete. Change a grade with `/tb_setgraderole`. Standalone businesses exist too and are not linked to a job.

**Cards, ATM and PIN.** The ATM is a small single column screen in the style of the terminal: pick a card, enter the PIN (on screen or with the keyboard), then see the balance, quick withdraw, other amount and deposit. A player orders a card for an account and sets a PIN (length from `Cards.MinPinLength` to `MaxPinLength`, common PINs are denied). The PIN is stored as a hash. The ATM asks for the card and PIN, too many wrong tries lock the card (`Atm.PinLockoutAttempts`) and it can be unlocked in the terminal. Lost cards can be replaced for `Cards.ReplacementFee`. Company cards can carry a daily limit per staff member.

**Terminal.** Clerk peds at `Bank.Zones` open a tablet with a Personal tab and a Business tab: dashboard, accounts, transfers, history and the feature panels below.

**Loans.** Fixed presets or custom amounts between the min and max. Interest is applied once to the principal and the total is split into installments. Missed installments are counted against `Loans.MaxMissedPayments`.

**Tax.** Off by default. Flat or bracket mode, applied on deposits, withdrawals or transfers as configured. The tax goes to a job's business, a given account number, or is burned.

**Billing.** Players and businesses send invoices to an account number or a player. Every invoice shows its number, the sending account name and number and the person behind it. The receiver pays from the UI. Paid, declined and cancelled invoices are kept in a "Past invoices" list in the invoice tab. Overdue invoices are swept on a timer, optionally charged automatically.

In the terminal, the invoice tab of the Personal tab lists your own accounts and every business where your role may invoice, so you pick who sends the bill. Which roles may invoice is set in `Config.Society.RoleCapabilities`.

**Standing orders.** Recurring transfers with an interval. After `MaxFailedRuns` failures in a row an order switches itself off.

**Savings.** Extra savings accounts pay interest on a timer. Withdrawals are locked for `WithdrawLockSeconds` after a deposit.

### Balance mirror

The default personal account is mirrored into the framework bank balance and job businesses into society accounts, so other scripts keep working. If another script changes the bank balance, the difference is booked as a correction in the history. Details are in [DEVELOPER.md](DEVELOPER.md).

## Commands

All commands need the framework group from `Config.Admin.Group`, the `tiltann_banking.admin` ace, or the server console.

| Command | Use |
| --- | --- |
| `/tb_setbalance [id] [amount]` | Set the default account of an online player. Clears that account's history. |
| `/tb_setsociety [job] [amount]` | Set a job business balance. Clears that account's history. |
| `/tb_setgraderole [job] [grade] [owner\|admin\|contributor]` | Set the business role for a job grade. |
| `/tb_debug [on\|off]` | Toggle debug logging. No argument flips it. |
| `/tb_version` | Show the installed version and run the update check. |
| `/banksociety` | Admin test command (in game only): list the jobs. |
| `/banksociety [job] [role]` | Add yourself to a job's business, default role `owner`. The business account is created if it does not exist yet. |
| `/banksocietyleave [job]` | Remove yourself from that business again. |

## Update check

On every start and restart the resource reads the `version` in `fxmanifest.lua` from the GitHub repository (branch `Updater.Branch`, default `main`) and compares it with the installed one. It prints the installed version, the latest version with its date and the matching section of `CHANGELOG.md`. There are no GitHub releases involved, the green Code button is the download. Set `Config.Updater.Enabled = false` to turn it off.

To publish an update: raise `version` in `fxmanifest.lua`, add a `## <version>` section to `CHANGELOG.md`, push to `main`.

## Exports

Server exports for balances, transfers, business money and invoices, and client exports to open the screens. Descriptions and examples are in [exports.md](exports.md).

## Billing menu

Press F7 (`Config.Billing.Key`, players can rebind it in the GTA key settings) or call the `OpenBilling` export. Pick where the bill comes from: one of your own accounts, or a business where your role is allowed to invoice. Enter a server id or an account number, an amount and a reason. When the bill is paid, the money goes to the account it was sent from, so a bill from a business pays the business. The same menu lists the bills you received so you can pay or decline them.

## For developers

Adding an inventory or framework, how the balance mirror works and how to build the UI are in [DEVELOPER.md](DEVELOPER.md).

---

This resource was created with the help of generative AI.
