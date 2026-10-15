--- @module server.billing.billing
--- Invoicing between any two accounts, a player's account or a business on
--- either side. "sender" issued the invoice (wants paying); "recipient" owes
--- it. Paying moves money recipient -> sender. Who may act on an account:
--- its owner (personal), or a business role with `invoice` (to send) /
--- `withdraw` (to pay), see TbBilling.CanUseAccount.

TbBilling = {}

--- Whether the caller may act for `accountId` in a billing sense.
---@param source integer
---@param accountId integer
---@param needed 'invoice'|'withdraw'
---@return boolean
function TbBilling.CanUseAccount(source, accountId, needed)
	local identifier = TbFramework.GetIdentifier(source)
	local account = identifier and TbAccounts.GetById(accountId)

	if not account then
		return false
	end

	if account.type == TbEnums.AccountType.SOCIETY then
		return TbSocietyPermissions.GetCapabilities(source, accountId)[needed] == true
	end

	return account.ownerIdentifier == identifier
end

--- Creates a pending invoice. No money moves until it's paid.
---@param senderAccountId integer
---@param recipientAccountId integer
---@param amount integer
---@param reason string?
---@param dueInDays integer?
---@param createdBy string?
---@param sharePercent integer? Business invoices: percent of the payment that goes to shareAccountId (the person who billed).
---@param shareAccountId integer?
---@return boolean ok
---@return string? errorReason
---@return integer? invoiceId
function TbBilling.SendInvoice(senderAccountId, recipientAccountId, amount, reason, dueInDays, createdBy, sharePercent, shareAccountId)
	if not Config.Billing.Enabled then
		return false, 'billing_disabled'
	end

	amount = TbUtils.RoundMoney(amount)

	if amount <= 0 or senderAccountId == recipientAccountId then
		return false, 'billing_invalid_amount'
	end

	if not TbAccounts.GetById(senderAccountId) or not TbAccounts.GetById(recipientAccountId) then
		return false, 'billing_recipient_not_found'
	end

	local ok, openCount = TbDb.SelectOne(
		"SELECT COUNT(*) AS count FROM tb_invoices WHERE sender_account_id = ? AND status = 'pending'",
		{ senderAccountId }
	)

	if ok and openCount and openCount.count >= Config.Billing.MaxOpenInvoicesPerSender then
		return false, 'billing_too_many_open'
	end

	local days = dueInDays or Config.Billing.DefaultDueDays
	local dueAt = days and os.date('!%Y-%m-%d %H:%M:%S', os.time() + days * 86400) or nil

	local insertOk, invoiceId = TbDb.Insert(
		'INSERT INTO tb_invoices (sender_account_id, recipient_account_id, amount, reason, due_at, created_by, share_percent, share_account_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
		{ senderAccountId, recipientAccountId, amount, TbUtils.CleanName(reason, 255), dueAt, createdBy, sharePercent or 0, shareAccountId }
	)

	if not insertOk then
		return false, 'billing_invalid_amount'
	end

	if TbLog then
		TbLog('billing', 'Invoice sent', {
			{ name = 'From account', value = tostring(senderAccountId) },
			{ name = 'To account', value = tostring(recipientAccountId) },
			{ name = 'Amount', value = tostring(amount) },
		})
	end

	return true, nil, invoiceId
end

--- Pays a pending invoice. The status flip is a race-safe
--- `UPDATE ... WHERE status = 'pending'` so two simultaneous pay attempts
--- can't both move money; a failed transfer rolls the status back.
---@param invoiceId integer
---@param payerIdentifier string?
---@param force boolean? Overdue collection: take it even if the account goes negative.
---@return boolean ok
---@return string? errorReason
function TbBilling.PayInvoice(invoiceId, payerIdentifier, force)
	if not Config.Billing.Enabled then
		return false, 'billing_disabled'
	end

	local ok, invoice = TbDb.SelectOne('SELECT * FROM tb_invoices WHERE id = ?', { invoiceId })

	if not ok or not invoice then
		return false, 'billing_not_found'
	end

	local claimOk, claimed = TbDb.Update(
		"UPDATE tb_invoices SET status = 'paid', resolved_at = NOW() WHERE id = ? AND status IN ('pending', 'overdue')",
		{ invoiceId }
	)

	if not claimOk or claimed == 0 then
		return false, 'billing_already_resolved'
	end

	local transferOk, transferError = TbAccounts.Transfer(
		invoice.recipient_account_id, invoice.sender_account_id, invoice.amount, TbEnums.TransactionType.INVOICE_PAYMENT,
		payerIdentifier, ('Invoice #%d'):format(invoiceId), { invoiceId = invoiceId }, force
	)

	if not transferOk then
		TbDb.Update("UPDATE tb_invoices SET status = 'pending', resolved_at = NULL WHERE id = ?", { invoiceId })
		return false, transferError == 'insufficient_funds' and 'tx_insufficient_funds' or 'billing_not_found'
	end

	-- Business invoice with a share: the person who billed gets their part from the business
	local sharePercent = tonumber(invoice.share_percent) or 0

	if sharePercent > 0 and invoice.share_account_id then
		local shareAmount = math.floor(invoice.amount * sharePercent / 100)

		if shareAmount > 0 then
			local shareOk, shareError = TbAccounts.Transfer(
				invoice.sender_account_id, invoice.share_account_id, shareAmount, TbEnums.TransactionType.INVOICE_PAYMENT,
				payerIdentifier, ('Invoice #%d share'):format(invoiceId), { invoiceId = invoiceId }
			)

			if not shareOk then
				TbLogger.Error('billing', 'invoice share could not be paid out, the business kept it', { invoice = invoiceId, error = shareError })
			end
		end
	end

	if TbLog then
		TbLog('billing', 'Invoice paid', {
			{ name = 'Invoice', value = tostring(invoiceId) },
			{ name = 'Amount', value = tostring(invoice.amount) },
		})
	end

	return true, nil
end

--- Declines a pending bill. Only bills sent from a personal account can be
--- declined, a bill from a business has to be paid.
---@param invoiceId integer
---@return boolean ok
---@return string? errorReason
function TbBilling.DeclineInvoice(invoiceId)
	if not Config.Billing.Enabled then
		return false, 'billing_disabled'
	end

	local ok, invoice = TbDb.SelectOne('SELECT sender_account_id FROM tb_invoices WHERE id = ?', { invoiceId })
	local sender = ok and invoice and TbAccounts.GetById(invoice.sender_account_id)

	if not sender then
		return false, 'billing_not_found'
	end

	if sender.type == TbEnums.AccountType.SOCIETY then
		return false, 'billing_cannot_decline'
	end

	local updated, affected = TbDb.Update(
		"UPDATE tb_invoices SET status = 'declined', resolved_at = NOW() WHERE id = ? AND status IN ('pending', 'overdue')",
		{ invoiceId }
	)

	if not updated or affected == 0 then
		return false, 'billing_already_resolved'
	end

	return true, nil
end

---@class TbInvoiceView
---@field id integer
---@field amount integer
---@field reason string?
---@field status TbInvoiceStatus
---@field dueAt string?
---@field createdAt string
---@field counterpartyName string
---@field counterpartyNumber string
---@field direction 'incoming'|'outgoing'

local nameCache = {}

--- Character name for an identifier: from the online player if there is one,
--- else from the ESX users table (cached, names do not change often).
---@param identifier string?
---@return string?
local function NameOf(identifier)
	if not identifier or identifier == '' then
		return nil
	end

	local source = TbFramework.GetSourceByIdentifier(identifier)
	local online = source and TbFramework.GetName(source)

	if online then
		nameCache[identifier] = online
		return online
	end

	if nameCache[identifier] == nil then
		local ok, row = pcall(MySQL.single.await, 'SELECT firstname, lastname FROM users WHERE identifier = ?', { identifier })
		nameCache[identifier] = ok and row and (('%s %s'):format(row.firstname or '', row.lastname or '')):match('^%s*(.-)%s*$') or false
	end

	return nameCache[identifier] or nil
end

---@param row table
---@param direction 'incoming'|'outgoing'
---@return TbInvoiceView
local function RowToView(row, direction)
	local otherId = direction == 'incoming' and row.sender_account_id or row.recipient_account_id
	local other = TbAccounts.GetById(otherId)

	return {
		id = row.id,
		amount = row.amount,
		reason = row.reason,
		status = row.status,
		dueAt = row.due_at,
		createdAt = row.created_at,
		counterpartyName = other and other.name or '?',
		counterpartyNumber = other and other.number or '?',
		-- the person behind the other account: who sent it, or who owns it
		counterpartyPerson = NameOf(direction == 'incoming' and row.created_by or (other and other.ownerIdentifier)) or NameOf(other and other.ownerIdentifier),
		direction = direction,
		-- bills from a person can be declined, bills from a business cannot
		canDecline = direction == 'incoming' and other ~= nil and other.type ~= TbEnums.AccountType.SOCIETY,
	}
end

--- Open invoices addressed TO an account (to pay) and open ones it SENT.
---@param accountId integer
---@return TbInvoiceView[] incoming
---@return TbInvoiceView[] outgoing
function TbBilling.GetOpenForAccount(accountId)
	local incoming, outgoing = {}, {}

	local ok, rows = TbDb.SelectMany(
		"SELECT * FROM tb_invoices WHERE recipient_account_id = ? AND status IN ('pending', 'overdue') ORDER BY created_at DESC",
		{ accountId }
	)

	if ok then
		for i, row in ipairs(rows) do
			incoming[i] = RowToView(row, 'incoming')
		end
	end

	local ok2, sent = TbDb.SelectMany(
		"SELECT * FROM tb_invoices WHERE sender_account_id = ? AND status IN ('pending', 'overdue') ORDER BY created_at DESC",
		{ accountId }
	)

	if ok2 then
		for i, row in ipairs(sent) do
			outgoing[i] = RowToView(row, 'outgoing')
		end
	end

	return incoming, outgoing
end

--- Settled invoices (paid, declined, cancelled) of an account, newest first,
--- both the ones it paid and the ones it sent.
---@param accountId integer
---@return TbInvoiceView[]
function TbBilling.GetPastForAccount(accountId)
	local past = {}

	local ok, rows = TbDb.SelectMany(
		"SELECT * FROM tb_invoices WHERE (recipient_account_id = ? OR sender_account_id = ?) AND status IN ('paid', 'declined', 'cancelled') ORDER BY COALESCE(resolved_at, created_at) DESC LIMIT 50",
		{ accountId, accountId }
	)

	if ok then
		for i, row in ipairs(rows) do
			past[i] = RowToView(row, row.recipient_account_id == accountId and 'incoming' or 'outgoing')
			past[i].resolvedAt = row.resolved_at
		end
	end

	return past
end

--- Open invoices addressed to any of a player's own accounts (dashboard badge).
---@param accountIds integer[]
---@return TbInvoiceView[]
function TbBilling.GetOpenAcross(accountIds)
	local all = {}

	for _, accountId in ipairs(accountIds) do
		local incoming = TbBilling.GetOpenForAccount(accountId)

		for _, view in ipairs(incoming) do
			all[#all + 1] = view
		end
	end

	return all
end

--- Bills from a business that are not paid by their due date are taken from the
--- account, even if it goes below zero (Config.Billing.AutoChargeOnOverdue).
--- Other bills, or all with it off, are only marked overdue.
local function RunOverdueSweep()
	local ok, dueInvoices = TbDb.SelectMany("SELECT id FROM tb_invoices WHERE status IN ('pending', 'overdue') AND due_at IS NOT NULL AND due_at <= NOW()")

	if not ok then
		return
	end

	for _, invoice in ipairs(dueInvoices) do
		TbSafe.Run('billing:invoice', function()
			local rowOk, row = TbDb.SelectOne('SELECT sender_account_id FROM tb_invoices WHERE id = ?', { invoice.id })
			local sender = rowOk and row and TbAccounts.GetById(row.sender_account_id)

			-- only bills from a business are collected, a bill from a person
			-- can be declined so it just stays overdue
			if Config.Billing.AutoChargeOnOverdue and sender and sender.type == TbEnums.AccountType.SOCIETY then
				local paid, reason = TbBilling.PayInvoice(invoice.id, nil, true)

				if not paid then
					TbLogger.Warn('billing', 'overdue invoice could not be collected', { invoice = invoice.id, reason = reason })
				end
			else
				TbDb.Update("UPDATE tb_invoices SET status = 'overdue' WHERE id = ? AND status = 'pending'", { invoice.id })
			end
		end)
	end
end

local sweepThreadStarted = false

function TbBilling.StartOverdueSweep()
	if sweepThreadStarted or not Config.Billing.Enabled then
		return
	end

	sweepThreadStarted = true

	CreateThread(function()
		while true do
			Wait(Config.Billing.OverdueSweepIntervalMs)
			TbSafe.Run('billing:overdue', RunOverdueSweep)
		end
	end)
end

-- Client-facing callbacks --------------------------------------------------

TbSafe.Callback('tiltann_banking:billing:getOpen', function(source, accountId)
	accountId = tonumber(accountId) or 0

	if not TbBilling.CanUseAccount(source, accountId, 'invoice') and not TbBilling.CanUseAccount(source, accountId, 'withdraw') then
		return { incoming = {}, outgoing = {}, past = {} }
	end

	local incoming, outgoing = TbBilling.GetOpenForAccount(accountId)
	return { incoming = incoming, outgoing = outgoing, past = TbBilling.GetPastForAccount(accountId) }
end)

TbSafe.Callback('tiltann_banking:billing:send', function(source, fromAccountId, recipientInput, amount, reason, sharePercent)
	fromAccountId = tonumber(fromAccountId) or 0

	if not TbBilling.CanUseAccount(source, fromAccountId, 'invoice') then
		return false, 'society_no_permission'
	end

	local recipient = TbAccounts.ResolveRecipient(recipientInput)

	if not recipient then
		return false, 'billing_recipient_not_found'
	end

	if recipient.type == TbEnums.AccountType.SOCIETY and not Config.Billing.AllowSocietyToSociety then
		local from = TbAccounts.GetById(fromAccountId)

		if from and from.type == TbEnums.AccountType.SOCIETY then
			return false, 'billing_invalid_amount'
		end
	end

	local identifier = TbFramework.GetIdentifier(source)
	local from = TbAccounts.GetById(fromAccountId)
	local share, shareAccountId = 0, nil

	-- A business invoice can pay part of the money to the person who billed
	if from and from.type == TbEnums.AccountType.SOCIETY and identifier then
		share = math.floor(math.max(0, math.min(tonumber(sharePercent) or 0, Config.Billing.MaxPersonalSharePercent)))

		if share > 0 then
			local own = TbAccounts.GetOrCreateDefault(identifier)
			shareAccountId = own and own.id or nil
			share = shareAccountId and share or 0
		end
	end

	local ok, errorKey = TbBilling.SendInvoice(fromAccountId, recipient.id, tonumber(amount) or 0, reason, nil, identifier, share, shareAccountId)

	-- tell the person who got the bill, if they are online
	if ok and recipient.ownerIdentifier then
		local target = TbFramework.GetSourceByIdentifier(recipient.ownerIdentifier)

		if target then
			TriggerClientEvent('tiltann_banking:invoiceReceived', target)
		end
	end

	return ok, errorKey
end)

-- Accounts the player can send bills from: their own personal accounts and
-- every business where their role may invoice. Used by the billing menu.
TbSafe.Callback('tiltann_banking:billing:getSenders', function(source)
	local identifier = TbFramework.GetIdentifier(source)

	if not identifier or not Config.Billing.Enabled then
		return {}
	end

	local senders = {}

	for _, account in ipairs(TbAccounts.ListForPlayer(identifier)) do
		if account.type == TbEnums.AccountType.PERSONAL then
			senders[#senders + 1] = account
		end
	end

	for _, business in ipairs(TbSocietyPermissions.ListBusinessesForPlayer(source)) do
		if business.capabilities and business.capabilities.invoice then
			local account = TbAccounts.GetById(business.accountId)

			if account then
				senders[#senders + 1] = account
			end
		end
	end

	return senders
end)

TbSafe.Callback('tiltann_banking:billing:decline', function(source, invoiceId)
	invoiceId = tonumber(invoiceId) or 0
	local ok, invoice = TbDb.SelectOne('SELECT recipient_account_id FROM tb_invoices WHERE id = ?', { invoiceId })

	if not ok or not invoice or not TbBilling.CanUseAccount(source, invoice.recipient_account_id, 'withdraw') then
		return false, 'society_no_permission'
	end

	return TbBilling.DeclineInvoice(invoiceId)
end)

TbSafe.Callback('tiltann_banking:billing:pay', function(source, invoiceId)
	invoiceId = tonumber(invoiceId) or 0
	local ok, invoice = TbDb.SelectOne('SELECT recipient_account_id FROM tb_invoices WHERE id = ?', { invoiceId })

	if not ok or not invoice or not TbBilling.CanUseAccount(source, invoice.recipient_account_id, 'withdraw') then
		return false, 'society_no_permission'
	end

	return TbBilling.PayInvoice(invoiceId, TbFramework.GetIdentifier(source))
end)

-- Players close to the caller, for the billing menu. Measured on the server.
TbSafe.Callback('tiltann_banking:billing:getNearby', function(source)
	local ped = GetPlayerPed(source)

	if not ped or ped == 0 then
		return {}
	end

	local origin = GetEntityCoords(ped)
	local nearby = {}

	for _, player in ipairs(TbFramework.GetPlayers()) do
		local otherPed = player.source ~= source and GetPlayerPed(player.source) or 0

		if otherPed ~= 0 and #(GetEntityCoords(otherPed) - origin) <= Config.Billing.NearbyRadius then
			nearby[#nearby + 1] = { id = player.source, name = TbFramework.GetName(player.source) or tostring(player.source) }
		end
	end

	table.sort(nearby, function(a, b)
		return a.id < b.id
	end)

	return nearby
end)
