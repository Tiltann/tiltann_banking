--- @module server.exports
--- Public server exports for third-party resources (shops, jobs, garages).
--- Every export is pcall-wrapped so a bad argument from another script
--- never crashes this one, failures return `false`/`nil`, never throw.
---
--- Usage from another resource:
---   exports.tiltann_banking:AddMoney(identifier, 500, 'Paycheck')
---   local ok = exports.tiltann_banking:RemoveMoney(identifier, 250, 'Shop purchase')
---   local balance = exports.tiltann_banking:GetBalance(identifier)
---   exports.tiltann_banking:AddSocietyMoney('mechanic', 1200, 'Repair job')

--- Wraps an export body so any error becomes a logged false/nil result.
---@param name string
---@param fn function
local function SafeExport(name, fn)
	exports(name, function(...)
		local args = table.pack(...)
		local ok, a, b = TbSafe.Run(('export:%s'):format(name), fn, ...)

		if not ok then
			TbLogger.Error('export', ('%s failed, check the caller\'s arguments'):format(name), { args = args })
			return false, nil
		end

		TbLogger.Debug('export', name, { args = args, result = a })
		return a, b
	end)
end

--- The player's default account (their "bank balance" from a script's point of view).
---@param identifier string
---@return TbAccount?
SafeExport('GetDefaultAccount', function(identifier)
	return TbAccounts.GetOrCreateDefault(identifier)
end)

---@param identifier string
---@return integer balance 0 if the player has no account yet.
SafeExport('GetBalance', function(identifier)
	local account = TbAccounts.GetOrCreateDefault(identifier)
	return account and account.balance or 0
end)

--- Credits the default account. Recorded as a deposit with your note.
---@param identifier string
---@param amount integer
---@param note string?
---@return boolean ok
SafeExport('AddMoney', function(identifier, amount, note)
	local account = TbAccounts.GetOrCreateDefault(identifier)
	return account ~= nil and TbAccounts.Credit(account.id, tonumber(amount) or 0, TbEnums.TransactionType.DEPOSIT, nil, note or 'External credit')
end)

--- Debits the default account. Returns false (nothing moves) if the balance
--- is insufficient, the atomic guard in TbAccounts.Debit.
---@param identifier string
---@param amount integer
---@param note string?
---@return boolean ok
SafeExport('RemoveMoney', function(identifier, amount, note)
	local account = TbAccounts.GetOrCreateDefault(identifier)
	return account ~= nil and TbAccounts.Debit(account.id, tonumber(amount) or 0, TbEnums.TransactionType.WITHDRAW, nil, note or 'External debit')
end)

--- Moves money from a player's default account to an account number or a server id.
---@param fromIdentifier string
---@param toNumber string|integer
---@param amount integer
---@param note string?
---@return boolean ok
---@return string? errorReason
SafeExport('TransferToNumber', function(fromIdentifier, toNumber, amount, note)
	local from = TbAccounts.GetOrCreateDefault(fromIdentifier)
	local to = TbAccounts.ResolveRecipient(toNumber)

	if not from or not to then
		return false, 'not_found'
	end

	return TbAccounts.Transfer(from.id, to.id, tonumber(amount) or 0, TbEnums.TransactionType.TRANSFER, fromIdentifier, note or 'External transfer')
end)

---@param number string
---@return TbAccount?
SafeExport('GetAccountByNumber', function(number)
	return TbAccounts.GetByNumber(number)
end)

-- The same three by server id, for scripts that only know the player's source.

---@param source integer
---@return integer balance
SafeExport('GetBalanceBySource', function(source)
	local identifier = TbFramework.GetIdentifier(source)
	local account = identifier and TbAccounts.GetOrCreateDefault(identifier)
	return account and account.balance or 0
end)

---@param source integer
---@param amount integer
---@param note string?
---@return boolean ok
SafeExport('AddMoneyBySource', function(source, amount, note)
	local identifier = TbFramework.GetIdentifier(source)
	local account = identifier and TbAccounts.GetOrCreateDefault(identifier)
	return account ~= nil and TbAccounts.Credit(account.id, tonumber(amount) or 0, TbEnums.TransactionType.DEPOSIT, nil, note or 'External credit')
end)

---@param source integer
---@param amount integer
---@param note string?
---@return boolean ok
SafeExport('RemoveMoneyBySource', function(source, amount, note)
	local identifier = TbFramework.GetIdentifier(source)
	local account = identifier and TbAccounts.GetOrCreateDefault(identifier)
	return account ~= nil and TbAccounts.Debit(account.id, tonumber(amount) or 0, TbEnums.TransactionType.WITHDRAW, nil, note or 'External debit')
end)

---@param jobName string
---@return integer balance
SafeExport('GetSocietyBalance', function(jobName)
	local account = TbAccounts.GetOrCreateJobAccount(jobName)
	return account and account.balance or 0
end)

---@param jobName string
---@param amount integer
---@param note string?
---@return boolean ok
SafeExport('AddSocietyMoney', function(jobName, amount, note)
	local account = TbAccounts.GetOrCreateJobAccount(jobName)
	return account ~= nil and TbAccounts.Credit(account.id, tonumber(amount) or 0, TbEnums.TransactionType.DEPOSIT, nil, note or 'External credit')
end)

---@param jobName string
---@param amount integer
---@param note string?
---@return boolean ok
SafeExport('RemoveSocietyMoney', function(jobName, amount, note)
	local account = TbAccounts.GetOrCreateJobAccount(jobName)
	return account ~= nil and TbAccounts.Debit(account.id, tonumber(amount) or 0, TbEnums.TransactionType.WITHDRAW, nil, note or 'External debit')
end)

--- Sends an invoice on behalf of any account (a job script billing a player,
--- for instance). Requires Config.Billing.Enabled.
---@param fromAccountId integer
---@param recipientInput string|integer Account number or server id.
---@param amount integer
---@param reason string?
---@return boolean ok
---@return string? errorReason
SafeExport('CreateInvoice', function(fromAccountId, recipientInput, amount, reason)
	local recipient = TbAccounts.ResolveRecipient(recipientInput)

	if not recipient then
		return false, 'recipient_not_found'
	end

	local ok, reasonKey = TbBilling.SendInvoice(tonumber(fromAccountId) or 0, recipient.id, tonumber(amount) or 0, reason, nil, nil)
	return ok, reasonKey
end)
