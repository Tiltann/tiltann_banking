# Exports

Exports for other resources (shops, jobs, garages, HUDs). They live in `server/exports.lua` and `client/exports.lua`.

* [Basics](#basics): identifiers, amounts, account choice, return values, the account table
* [Reading accounts](#reading-accounts): `GetAccounts`, `GetDefaultAccount`, `GetAccountByNumber`, `GetAccountOwner`
* [Balances](#balances): `GetBalance`, `GetTotalBalance`
* [Adding and removing money](#adding-and-removing-money): `AddMoney`, `RemoveMoney`
* [By server id](#by-server-id): the same with a `source`
* [Transfers](#transfers): `TransferToNumber`
* [Business accounts](#business-accounts): `GetSocietyAccountByName`, `GetSocietyBalance`, `AddSocietyMoney`, `RemoveSocietyMoney`
* [Invoices](#invoices): `CreateInvoice`
* [Client exports](#client-exports)

---

## Basics

### Safe by design

Every server export is wrapped. A wrong argument or an internal error **never throws** in your script. The export writes an error to the console and returns `false` (or `nil`) instead, so check the result.

### Identifier

Functions without `BySource` take the player's framework identifier. With ESX that is `xPlayer.identifier` (for example `char1:abc123...`). It works for offline players too.

```lua
local identifier = ESX.GetPlayerFromId(source).identifier
```

### Amounts

Whole numbers. A decimal is rounded to the nearest whole number (`10.5` becomes `11`). Zero, negative numbers, text and `nil` count as an invalid amount and nothing moves.

### Notes

The optional `note` is shown in the player's transaction history. Without one the history says "External credit", "External debit" or "External transfer".

### Which account? (the `account` argument)

A player has one **main account**, and can have more personal accounts and savings accounts. Exports that take `account` use it like this:

| `account` | Meaning |
| --- | --- |
| left out (`nil`) | The main account. |
| `1` | The main account. |
| `2`, `3`, ... | The next accounts in the order `GetAccounts` returns them: personal accounts first, then savings accounts, oldest first. |
| `'920-48271039'` | An account number (text). The account has to belong to this player, otherwise it counts as not found. |

If the account does not exist, balance exports return `0` and money exports return `false, 'not_found'`.

### Recipients (numberOrServerId)

Where an export asks for a recipient, give one of:

| Value | Meaning |
| --- | --- |
| `'920-48271039'` | An account number. That exact account. |
| `12` | A server id. That player's main account. The player has to be online. |
| `'char1:abc123'` | An identifier (text that is not an account number). That player's main account, online or offline. |

### Return values

Money exports return two values: `ok, reason`. `ok` is `true` on success. On failure `ok` is `false` and `reason` is one of these texts:

| `reason` | Meaning |
| --- | --- |
| `invalid_amount` | The amount is zero, negative or not a number. |
| `not_found` | The player, account or recipient does not exist. |
| `insufficient_funds` | The balance is too low. Nothing moved. |
| `savings_locked` | A savings account is locked after a deposit (`Config.Savings.WithdrawLockSeconds`). |
| `same_account` | Sender and receiver are the same account. |
| `credit_failed` | The receiving side failed, the money was returned to the sender. |

### The account table

Several exports return an account as a table with these fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | number | Internal account id. Needed for `CreateInvoice`. |
| `type` | text | `'personal'`, `'savings'` or `'society'` (business). |
| `ownerIdentifier` | text or `nil` | The owner. `nil` for business accounts. |
| `jobName` | text or `nil` | The linked job (business accounts), otherwise `nil`. |
| `number` | text | The account number, for example `'920-48271039'`. |
| `name` | text | The name of the account. |
| `balance` | number | The current balance. |
| `isDefault` | boolean | `true` for the main account. |
| `isTreasury` | boolean | `true` for a business treasury account. |
| `interestRate` | number or `nil` | Interest rate in percent (savings accounts). |
| `lockedUntil` | date or `nil` | Savings: no withdrawal before this time. |
| `historyClearedAt` | date or `nil` | The time the player cleared the history. |
| `createdAt` | date | When the account was created. |
| `index` | number | **Only in `GetAccounts`.** The position to pass as `account`. |

Dates come as the database delivers them: usually a number (milliseconds since 1970), or text `'2026-10-16 12:30:00'` if your oxmysql uses string dates.

---

## Reading accounts

### `GetAccounts(identifier)` and `GetAccountsBySource(source)`

All personal and savings accounts a player owns.

| | |
| --- | --- |
| **Takes** | `identifier` (text), or `source` (number) for the `BySource` version. |
| **Returns** | A list of [account tables](#the-account-table), main account first. Every entry has an `index`. An empty list if the player is not logged in (`BySource`). |

```lua
for _, account in ipairs(exports.tiltann_banking:GetAccounts(identifier)) do
    print(account.index, account.type, account.number, account.name, account.balance)
end
-- 1  personal  920-48271039  Main account  18076
-- 2  savings   920-55120044  Holiday        4000
```

### `GetDefaultAccount(identifier)`

The main account. It is created when the player has none yet.

| | |
| --- | --- |
| **Takes** | `identifier` (text). |
| **Returns** | The main [account table](#the-account-table). |

```lua
local account = exports.tiltann_banking:GetDefaultAccount(identifier)
print(account.id, account.number, account.balance)
```

### `GetAccountByNumber(number)`

Looks an account up by its number. Works for every account type, including business accounts.

| | |
| --- | --- |
| **Takes** | `number` (text), for example `'920-48271039'`. |
| **Returns** | The [account table](#the-account-table), or `nil` if the number does not exist. |

```lua
local account = exports.tiltann_banking:GetAccountByNumber('920-48271039')

if account then
    print(account.name, account.balance)
end
```

### `GetAccountOwner(number)`

Who an account belongs to.

| | |
| --- | --- |
| **Takes** | `number` (text), the account number. |
| **Returns** | A table, or `nil` if the number does not exist. |

The table:

| Field | Type | Meaning |
| --- | --- | --- |
| `number` | text | The account number. |
| `type` | text | `'personal'`, `'savings'` or `'society'`. |
| `accountName` | text | The name of the account. |
| `identifier` | text or `nil` | The owner's identifier. `nil` for business accounts. |
| `name` | text or `nil` | The owner's character name (the online character, or the ESX `users` table for offline players). `nil` for business accounts. |
| `online` | boolean | `true` if the owner is online right now. |
| `source` | number or `nil` | The owner's server id, only when `online`. |
| `jobName` | text or `nil` | The job, for business accounts. |

```lua
local owner = exports.tiltann_banking:GetAccountOwner('920-48271039')

if owner and owner.online then
    TriggerClientEvent('ox_lib:notify', owner.source, { description = 'Somebody looked up your account.' })
elseif owner then
    print(('Account belongs to %s (offline)'):format(owner.name or owner.identifier))
end
```

---

## Balances

### `GetBalance(identifier, account)`

The balance of one account.

| | |
| --- | --- |
| **Takes** | `identifier` (text). `account` (optional, see [Which account?](#which-account-the-account-argument)). |
| **Returns** | The balance (number). `0` if the account does not exist. |

```lua
local main    = exports.tiltann_banking:GetBalance(identifier)
local second  = exports.tiltann_banking:GetBalance(identifier, 2)
local byNumber = exports.tiltann_banking:GetBalance(identifier, '920-55120044')
```

### `GetTotalBalance(identifier)`

All money of a player: the sum of every personal and savings account.

| | |
| --- | --- |
| **Takes** | `identifier` (text). |
| **Returns** | The total (number). |

```lua
if exports.tiltann_banking:GetTotalBalance(identifier) >= 100000 then
    -- rich enough for the penthouse
end
```

---

## Adding and removing money

### `AddMoney(identifier, amount, note, account)`

Adds money to an account. Shown in the history as a deposit.

| | |
| --- | --- |
| **Takes** | `identifier` (text), `amount` (number), `note` (optional text), `account` (optional, see [Which account?](#which-account-the-account-argument)). |
| **Returns** | `ok` (boolean), `reason` (text, only when `ok` is `false`: `invalid_amount` or `not_found`). |

```lua
-- paycheck to the main account
exports.tiltann_banking:AddMoney(identifier, 1500, 'Paycheck')

-- to the second account
exports.tiltann_banking:AddMoney(identifier, 200, 'Bonus', 2)

-- to a specific account number
local ok, reason = exports.tiltann_banking:AddMoney(identifier, 200, 'Bonus', '920-55120044')
```

### `RemoveMoney(identifier, amount, note, account)`

Takes money from an account. If the balance is too low, **nothing moves**.

| | |
| --- | --- |
| **Takes** | `identifier` (text), `amount` (number), `note` (optional text), `account` (optional). |
| **Returns** | `ok` (boolean), `reason` (text, only when `ok` is `false`: `insufficient_funds`, `invalid_amount`, `not_found` or `savings_locked`). |

```lua
local ok, reason = exports.tiltann_banking:RemoveMoney(identifier, 250, 'Shop purchase')

if ok then
    exports.ox_inventory:AddItem(source, 'bread', 1)
elseif reason == 'insufficient_funds' then
    TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'Not enough money' })
end

-- from the second account
exports.tiltann_banking:RemoveMoney(identifier, 250, 'Shop purchase', 2)
```

---

## By server id

For scripts that only know the player's `source`. They do the same as the versions above, the first argument is the server id.

| Export | Takes | Returns |
| --- | --- | --- |
| `GetBalanceBySource(source, account)` | `source`, optional `account` | Balance (number), `0` if the player is not logged in or the account does not exist. |
| `GetTotalBalanceBySource(source)` | `source` | The total of all accounts (number), `0` if not logged in. |
| `AddMoneyBySource(source, amount, note, account)` | `source`, `amount`, optional `note`, optional `account` | `ok, reason` as in `AddMoney`. |
| `RemoveMoneyBySource(source, amount, note, account)` | `source`, `amount`, optional `note`, optional `account` | `ok, reason` as in `RemoveMoney`. |
| `GetAccountsBySource(source)` | `source` | List of account tables, see `GetAccounts`. |

If the player is not logged in, the money functions return `false, 'not_found'`.

```lua
RegisterNetEvent('myshop:buy', function()
    local src = source

    if exports.tiltann_banking:RemoveMoneyBySource(src, 100, 'Myshop') then
        -- give the item
    end
end)
```

---

## Transfers

### `TransferToNumber(fromIdentifier, numberOrServerId, amount, note)`

Moves money from a player's **main account** to another account.

| | |
| --- | --- |
| **Takes** | `fromIdentifier` (text), the sender. `numberOrServerId`, the receiver (see [Recipients](#recipients-numberorserverid)). `amount` (number). `note` (optional text). |
| **Returns** | `ok` (boolean), `reason` (text, only when `ok` is `false`: `not_found`, `invalid_amount`, `same_account`, `insufficient_funds`, `savings_locked` or `credit_failed`). |

```lua
local ok, reason = exports.tiltann_banking:TransferToNumber(identifier, '920-48271039', 500, 'Rent')

if not ok then
    print('Transfer failed: ' .. tostring(reason))
end

-- to the player with server id 12
exports.tiltann_banking:TransferToNumber(identifier, 12, 100, 'Gift')
```

---

## Business accounts

Every job has a business account, created the first time it is needed. A business account is an [account table](#the-account-table) with `type = 'society'`.

### `GetSocietyAccountByName(name)`

Finds the business account of a job.

| | |
| --- | --- |
| **Takes** | `name` (text): the job name (`'mechanic'`), the business name or the job label. Upper and lower case do not matter. |
| **Returns** | The [account table](#the-account-table), or `nil` for an unknown name. If the job exists in your framework but has no business account yet, it is created. |

```lua
local society = exports.tiltann_banking:GetSocietyAccountByName('mechanic')

if society then
    print(society.id, society.number, society.name, society.balance)
end
```

Use `society.id` as `fromAccountId` for `CreateInvoice`. Players pay to `society.number`.

### `GetSocietyBalance(job)`

| | |
| --- | --- |
| **Takes** | `job` (text), the job name. |
| **Returns** | The balance of the business (number). |

```lua
local balance = exports.tiltann_banking:GetSocietyBalance('mechanic')
```

### `AddSocietyMoney(job, amount, note)`

| | |
| --- | --- |
| **Takes** | `job` (text), `amount` (number), `note` (optional text). |
| **Returns** | `true` on success, `false` otherwise. |

```lua
exports.tiltann_banking:AddSocietyMoney('mechanic', 1200, 'Repair job')
```

### `RemoveSocietyMoney(job, amount, note)`

Takes money from the business. If the balance is too low, nothing moves.

| | |
| --- | --- |
| **Takes** | `job` (text), `amount` (number), `note` (optional text). |
| **Returns** | `true` on success, `false` if the balance is too low or the amount is invalid. |

```lua
if exports.tiltann_banking:RemoveSocietyMoney('mechanic', 800, 'Parts') then
    -- the business paid
end
```

---

## Invoices

### `CreateInvoice(fromAccountId, numberOrServerId, amount, reason)`

Sends an invoice from any account, for example a job script billing a player. When the receiver pays, the money goes to the sending account, so use a business account to bill for the business. Needs `Config.Billing.Enabled`.

| | |
| --- | --- |
| **Takes** | `fromAccountId` (number): the `id` of the sending account. `numberOrServerId`: the receiver (see [Recipients](#recipients-numberorserverid)). `amount` (number). `reason` (optional text, shown on the invoice). |
| **Returns** | `ok` (boolean), `reason` (text, only when `ok` is `false`). |

Reasons: `recipient_not_found`, `billing_disabled`, `billing_invalid_amount`, `billing_recipient_not_found` and `billing_too_many_open` (the sender already has `Config.Billing.MaxOpenInvoicesPerSender` open invoices).

```lua
local society = exports.tiltann_banking:GetSocietyAccountByName('mechanic')

if society then
    local ok, reason = exports.tiltann_banking:CreateInvoice(society.id, targetServerId, 2500, 'Vehicle repair')

    if not ok then
        print('Invoice failed: ' .. tostring(reason))
    end
end
```

---

## Client exports

These open or close the bank screens. They are client side, so call them from a client script.

| Export | Takes | Returns | What it does |
| --- | --- | --- | --- |
| `OpenBank()` | nothing | `true` | Opens the bank terminal (tablet). |
| `OpenAtm()` | nothing | `true` | Opens the ATM screen. |
| `OpenBilling()` | nothing | `true` | Opens the billing menu (also on F7, `Config.Billing.Key`). |
| `CloseUi()` | nothing | `true` | Closes whatever is open. |
| `IsUiOpen()` | nothing | `true` while a bank screen is open, otherwise `false` | Tells you if a bank screen is open. |
| `RefreshUi()` | nothing | `true` | Reloads the data of the open screen. |

Each one returns `false` if something went wrong inside. Opening a screen does nothing when one is already open.

```lua
-- open the ATM from your own interaction
exports.tiltann_banking:OpenAtm()

-- a custom target with ox_target
exports.ox_target:addModel({ 'prop_atm_01' }, {
    {
        label = 'Use ATM',
        icon = 'fas fa-credit-card',
        onSelect = function()
            exports.tiltann_banking:OpenAtm()
        end,
    },
})

-- do not open another menu while the bank is open
if exports.tiltann_banking:IsUiOpen() then
    return
end
```

With `Config.Interaction.Mode = 'custom'` nothing is set up for you. `Interaction.Custom(openAtm, openBank, openBilling)` is called once on the client with functions that open the same screens.

---

## Notes

* **Mirror.** The main account is mirrored into the framework bank balance and job businesses into society accounts, so other scripts that read the framework balance keep working. These exports are the cleanest way to change money, because they also write the transaction history. Changing the framework bank directly also works, the difference is booked as a correction in the history.
* **Debug.** With `/tb_debug on` every export call is printed in the console with its arguments and result.
