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

**Which account?** `GetBalance`, `AddMoney`, `RemoveMoney` and `TransferToNumber` always use the player's **default** account (the one that is mirrored into the framework bank balance). Other accounts and savings are not touched by these.

---

## Server exports

### Player balance

#### `GetBalance(identifier)`

Returns the balance of the player's default account as an integer. Returns `0` if the player has no account yet (it is created on first use).

```lua
local balance = exports.tiltann_banking:GetBalance(identifier)

if balance >= 5000 then
    -- the player can afford it
end
```

#### `GetDefaultAccount(identifier)`

Returns the default account as a table, creating it if needed.

```lua
local account = exports.tiltann_banking:GetDefaultAccount(identifier)
print(account.id, account.number, account.name, account.balance)
```

Fields: `id`, `type` (`personal`, `savings` or `society`), `ownerIdentifier`, `jobName`, `number`, `name`, `balance`, `isDefault`, `isTreasury`, `interestRate`, `lockedUntil`, `historyClearedAt`, `createdAt`.

#### `AddMoney(identifier, amount, note)`

Adds money to the default account. Booked as a deposit. Returns `true` on success.

```lua
-- paycheck
exports.tiltann_banking:AddMoney(identifier, 1500, 'Paycheck')
```

#### `RemoveMoney(identifier, amount, note)`

Takes money from the default account. If the balance is too low, **nothing moves** and it returns `false`.

```lua
-- shop purchase
if exports.tiltann_banking:RemoveMoney(identifier, 250, 'Shop purchase') then
    exports.ox_inventory:AddItem(source, 'bread', 1)
else
    TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'Not enough money' })
end
```

### The same by server id

For scripts that only know the player's `source`. If the player is not logged in, `GetBalanceBySource` returns `0` and the others return `false`.

```lua
exports.tiltann_banking:GetBalanceBySource(source)               -- integer
exports.tiltann_banking:AddMoneyBySource(source, amount, note)   -- boolean
exports.tiltann_banking:RemoveMoneyBySource(source, amount, note) -- boolean
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
