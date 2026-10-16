# Exports

Exports for other resources (shops, jobs, garages, HUDs). They live in `server/exports.lua` and `client/exports.lua`.

All server exports are wrapped: a bad argument or an internal error never throws in your script. The export logs an error in the console and returns `false` (or `nil`) instead.

## Basics

**Identifier.** Functions without `BySource` take the player's framework identifier. With ESX that is `xPlayer.identifier` (for example `char1:abc123...`). It works for offline players too.

```lua
local identifier = ESX.GetPlayerFromId(source).identifier
```

**Amounts.** Whole numbers only. Zero or negative amounts are refused.

**Notes.** The optional `note` shows up in the player's transaction history. Without one, the history says "External credit" or "External debit".

**Recipients.** Wherever a recipient is asked for, you can give an account number (`920-48271039`) or a server id (`12`). A server id means that player's main account, so the player has to be online.

**Which account?** Without an `account` argument the exports use the player's **main** account (the one mirrored into the framework bank balance). See "Accounts: which one?" to use another account or a savings account. `TransferToNumber` always sends from the main account.

---

## Server exports

### Accounts: which one?

A player has a **main account** and can have more personal accounts and savings accounts. `GetBalance`, `AddMoney`, `RemoveMoney` and their `BySource` versions take an optional last argument `account` that picks one of them:

| `account` | Meaning |
| --- | --- |
| left out | The main account. |
| `1` | The main account. |
| `2`, `3`, ... | The next accounts, in the order of `GetAccounts` (personal accounts first, then savings accounts, oldest first). |
| `'920-48271039'` | An account number. It has to belong to that player, otherwise nothing happens. |

Use `GetAccounts` to see what a player has. If the account does not exist, the functions return `false, 'not_found'`.

### Player balance

#### `GetAccounts(identifier)` / `GetAccountsBySource(source)`

Returns a list of all personal and savings accounts the player owns, main account first. Every entry has an `index` that you can pass as `account`, and a `number`.

```lua
for _, account in ipairs(exports.tiltann_banking:GetAccounts(identifier)) do
    print(account.index, account.type, account.number, account.name, account.balance)
end
-- 1  personal  920-48271039  Main account  18076
-- 2  savings   920-55120044  Holiday        4000
```

Fields: `index`, `id`, `type` (`personal` or `savings`), `ownerIdentifier`, `number`, `name`, `balance`, `isDefault`, `interestRate`, `lockedUntil`, `historyClearedAt`, `createdAt`.

#### `GetBalance(identifier, account)`

Balance of one account, an integer. Returns `0` if the account does not exist. Without `account` it is the main account.

```lua
local main = exports.tiltann_banking:GetBalance(identifier)
local savings = exports.tiltann_banking:GetBalance(identifier, 2)
local byNumber = exports.tiltann_banking:GetBalance(identifier, '920-55120044')
```

#### `GetTotalBalance(identifier)` / `GetTotalBalanceBySource(source)`

All money of the player: the sum of every personal and savings account.

```lua
local total = exports.tiltann_banking:GetTotalBalance(identifier)

if total >= 100000 then
    -- rich enough for the penthouse
end
```

#### `GetDefaultAccount(identifier)`

Returns the main account as a table, creating it if needed.

```lua
local account = exports.tiltann_banking:GetDefaultAccount(identifier)
print(account.id, account.number, account.name, account.balance)
```

#### `AddMoney(identifier, amount, note, account)`

Adds money. Booked as a deposit. Returns `ok, reason`. Reasons: `invalid_amount`, `not_found` (no such account).

```lua
-- paycheck to the main account
exports.tiltann_banking:AddMoney(identifier, 1500, 'Paycheck')

-- interest bonus to the second account
exports.tiltann_banking:AddMoney(identifier, 200, 'Bonus', 2)

-- to a specific account number
exports.tiltann_banking:AddMoney(identifier, 200, 'Bonus', '920-55120044')
```

#### `RemoveMoney(identifier, amount, note, account)`

Takes money. If the balance is too low, **nothing moves**. Returns `ok, reason`. Reasons: `insufficient_funds`, `invalid_amount`, `not_found`, `savings_locked` (a savings account is locked after a deposit).

```lua
local ok, reason = exports.tiltann_banking:RemoveMoney(identifier, 250, 'Shop purchase')

if ok then
    exports.ox_inventory:AddItem(source, 'bread', 1)
else
    print('Payment failed: ' .. tostring(reason))
end

-- from the second account
exports.tiltann_banking:RemoveMoney(identifier, 250, 'Shop purchase', 2)
```

### The same by server id

For scripts that only know the player's `source`. If the player is not logged in, `GetBalanceBySource` and `GetTotalBalanceBySource` return `0` and the others return `false, 'not_found'`.

```lua
exports.tiltann_banking:GetBalanceBySource(source, account)
exports.tiltann_banking:GetTotalBalanceBySource(source)
exports.tiltann_banking:AddMoneyBySource(source, amount, note, account)
exports.tiltann_banking:RemoveMoneyBySource(source, amount, note, account)
```

```lua
RegisterNetEvent('myshop:buy', function()
    local src = source

    if exports.tiltann_banking:RemoveMoneyBySource(src, 100, 'Myshop') then
        -- give the item
    end
end)
```

### Transfers

#### `TransferToNumber(fromIdentifier, numberOrServerId, amount, note)`

Moves money from a player's default account to another account. Returns `ok, reason`.

Reasons: `not_found`, `invalid_amount`, `same_account`, `insufficient_funds`, `savings_locked`.

```lua
local ok, reason = exports.tiltann_banking:TransferToNumber(identifier, '920-48271039', 500, 'Rent')

if not ok then
    print('Transfer failed: ' .. tostring(reason))
end
```

#### `GetAccountByNumber(number)`

Returns the account table for an account number, or `nil`.

```lua
local account = exports.tiltann_banking:GetAccountByNumber('920-48271039')

if account then
    print(account.name, account.balance)
end
```

#### `GetSocietyAccountByName(name)`

The business account of a job. `name` is the job name (`'mechanic'`) or the business name or job label, upper and lower case do not matter. If the job exists in your framework but has no business account yet, it is created. Returns `nil` for an unknown name.

```lua
local society = exports.tiltann_banking:GetSocietyAccountByName('mechanic')

if society then
    print(society.id, society.number, society.name, society.balance)
end
```

The `id` is what `CreateInvoice` needs as `fromAccountId`, the `number` is what players pay to:

```lua
local society = exports.tiltann_banking:GetSocietyAccountByName('mechanic')
exports.tiltann_banking:CreateInvoice(society.id, targetServerId, 2500, 'Vehicle repair')
```

#### `GetAccountOwner(number)`

Who an account belongs to, from its account number. Returns `nil` if the number does not exist.

```lua
local owner = exports.tiltann_banking:GetAccountOwner('920-48271039')

if owner then
    print(owner.name, owner.identifier, owner.online, owner.source)
end
```

Fields: `number`, `type`, `accountName`, `identifier` (the owner), `name` (character name), `online`, `source` (only when online) and `jobName`. The name comes from the online character, or from the ESX `users` table for offline players. A business account has no owner, you get its `jobName` instead and `identifier`/`name` are `nil`.

### Business (society) accounts

Every job has a business account, created on first use. The job name is the framework job name (`police`, `mechanic`, ...).

```lua
exports.tiltann_banking:GetSocietyBalance(job)                -- integer
exports.tiltann_banking:AddSocietyMoney(job, amount, note)    -- boolean
exports.tiltann_banking:RemoveSocietyMoney(job, amount, note) -- boolean, false if not enough
```

```lua
-- the repair paid the mechanic business
exports.tiltann_banking:AddSocietyMoney('mechanic', 1200, 'Repair job')

-- the business buys something
if exports.tiltann_banking:RemoveSocietyMoney('mechanic', 800, 'Parts') then
    -- ...
end
```

### Invoices

#### `CreateInvoice(fromAccountId, numberOrServerId, amount, reason)`

Sends an invoice on behalf of any account, for example a job script billing a player. Returns `ok, reason`. Needs `Config.Billing.Enabled`.

The money goes to `fromAccountId` when the invoice is paid, so use a business account id to bill for a business.

```lua
-- look up the business account by its number (shown in the terminal)
local society = exports.tiltann_banking:GetAccountByNumber('920-11223344')

if society then
    local ok, reason = exports.tiltann_banking:CreateInvoice(society.id, targetServerId, 2500, 'Vehicle repair')

    if not ok then
        print('Invoice failed: ' .. tostring(reason))
    end
end
```

Reasons: `recipient_not_found`, `billing_disabled`, `billing_invalid_amount`, `billing_recipient_not_found`, `billing_too_many_open`.

---

## Client exports

These open or close the bank screens. All of them return `true`, except `IsUiOpen`.

| Export | What it does |
| --- | --- |
| `OpenBank()` | Opens the bank terminal (tablet). |
| `OpenAtm()` | Opens the ATM screen. |
| `OpenBilling()` | Opens the billing menu (also on F7, `Config.Billing.Key`). |
| `CloseUi()` | Closes whatever is open. |
| `IsUiOpen()` | `true` while a bank screen is open. |
| `RefreshUi()` | Reloads the data of the open screen. |

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

If you set `Config.Interaction.Mode = 'custom'`, nothing is set up for you. `Interaction.Custom(openAtm, openBank, openBilling)` is called once with the same functions, you can also use these exports instead.

---

## Notes

* **Mirror.** The default account is mirrored into the framework bank balance and job businesses into society accounts, so other scripts that read the framework balance keep working. These exports are the cleanest way to change money, because they also write the transaction history.
* **Changing the framework bank directly** also works, the difference is booked as a correction in the history.
* **Logs.** With `/tb_debug on` every export call is printed in the console with its arguments.
