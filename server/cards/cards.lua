--- @module server.cards.cards
--- Bank card issuance, PIN management and self-service locking. One
--- physical ox_inventory card per (holder, account): a personal card for
--- each of your own accounts, a company card for a business you may spend
--- from. Savings accounts never get a card (they're not usable at an ATM).
---
--- The PIN is NEVER stored in item metadata (client-visible, inventory-
--- admin-editable), only its salted SHA-256 hash lives in tb_cards, the
--- sole source of truth for verification. Metadata carries just the
--- cosmetic card number and a serial.

TbCards = {}

---@param cardId integer
---@return table? row
local function GetCardById(cardId)
	local ok, row = TbDb.SelectOne('SELECT * FROM tb_cards WHERE id = ?', { cardId })

	if not ok or not row then
		return nil
	end

	return row
end

---@return string? cardNumber nil when no free number was found
local function GenerateUniqueCardNumber()
	for _ = 1, 10 do
		local candidate = TbUtils.RandomDigits(16)
		local ok, existing = TbDb.SelectOne('SELECT id FROM tb_cards WHERE number = ?', { candidate })

		if ok and not existing then
			return candidate
		end
	end

	TbLogger.Error('cards', 'could not generate a unique card number after 10 attempts')
	return nil
end

--- Shapes a card row (plus its account) for the client, never the PIN
--- hash/salt, never the full number.
---@param row table
---@param account TbAccount?
---@return TbCardSummary
function TbCards.RowToSummary(row, account)
	account = account or TbAccounts.GetById(row.account_id)

	return {
		id = row.id,
		accountId = row.account_id,
		accountName = account and account.name or '?',
		accountNumber = account and account.number or '?',
		isCompany = account ~= nil and account.type == TbEnums.AccountType.SOCIETY,
		maskedNumber = TbUtils.MaskCardNumber(row.number),
		status = row.status,
		isLocked = TbUtils.ToBool(row.is_locked),
		hasPin = row.pin_hash ~= nil,
	}
end

---@class TbCardSummary
---@field id integer
---@field accountId integer
---@field accountName string
---@field accountNumber string
---@field isCompany boolean
---@field maskedNumber string
---@field status TbCardStatus
---@field isLocked boolean
---@field hasPin boolean

--- Every live card the player holds, own accounts' cards and company cards.
---@param identifier string
---@return TbCardSummary[]
function TbCards.ListForHolder(identifier)
	local ok, rows = TbDb.SelectMany(
		[[SELECT c.* FROM tb_cards c
			JOIN tb_accounts a ON a.id = c.account_id AND a.deleted_at IS NULL
			WHERE c.holder_identifier = ? AND c.status IN ('active', 'blocked')
			ORDER BY a.is_default DESC, a.type ASC, c.created_at ASC]],
		{ identifier }
	)

	if not ok then
		return {}
	end

	local cards = {}

	for i, row in ipairs(rows) do
		cards[i] = TbCards.RowToSummary(row)
	end

	return cards
end

--- Whether `source` may hold a card on `account`: own personal account, or
--- a business they can spend from. Savings accounts never qualify.
---@param source integer
---@param identifier string
---@param account TbAccount
---@return boolean allowed
---@return string? errorReason
local function CanHoldCard(source, identifier, account)
	if account.type == TbEnums.AccountType.PERSONAL then
		return account.ownerIdentifier == identifier, 'account_not_found'
	end

	if account.type == TbEnums.AccountType.SOCIETY then
		local capabilities = TbSocietyPermissions.GetCapabilities(source, account.id)
		return capabilities.deposit or capabilities.withdraw, 'society_no_permission'
	end

	return false, 'card_not_allowed'
end

--- Issues a card for an account the player may hold one on.
---@param source integer
---@param identifier string
---@param accountId integer
---@return boolean ok
---@return string? errorReason
---@return integer? cardId
function TbCards.Request(source, identifier, accountId)
	if not Config.Cards.Enabled then
		return false, 'card_disabled'
	end

	local account = TbAccounts.GetById(accountId)

	if not account then
		return false, 'account_not_found'
	end

	local allowed, reason = CanHoldCard(source, identifier, account)

	if not allowed then
		return false, reason
	end

	local limit = Config.Cards.AllowMultiplePerAccount and (tonumber(Config.Cards.MaxPerAccount) or 1) or 1
	local countOk, countRow = TbDb.SelectOne(
		"SELECT COUNT(*) AS count FROM tb_cards WHERE holder_identifier = ? AND account_id = ? AND status IN ('active', 'blocked')",
		{ identifier, accountId }
	)

	if countOk and countRow and countRow.count >= limit then
		return false, limit == 1 and 'card_already_owned' or 'card_limit_reached'
	end

	local cardNumber = GenerateUniqueCardNumber()

	if not cardNumber then
		return false, 'card_inventory_failed'
	end

	local insertOk, cardId = TbDb.Insert(
		'INSERT INTO tb_cards (account_id, holder_identifier, number) VALUES (?, ?, ?)',
		{ accountId, identifier, cardNumber }
	)

	if not insertOk or not cardId then
		return false, 'card_inventory_failed'
	end

	local itemOk, serial = TbInventoryProvider.AddItem(source, Config.Cards.ItemName, {
		cardNumber = cardNumber,
		accountNumber = account.number,
		accountName = account.name,
		ownerIdentifier = identifier,
		linkedAt = os.time(),
	})

	if not itemOk then
		-- Roll back the row rather than leaving a card record with no item.
		TbDb.Update('DELETE FROM tb_cards WHERE id = ?', { cardId })
		return false, 'card_inventory_failed'
	end

	TbDb.Update('UPDATE tb_cards SET inventory_serial = ? WHERE id = ?', { serial, cardId })

	if TbLog then
		TbLog('cards', 'Bank card issued', {
			{ name = 'Holder', value = identifier },
			{ name = 'Account', value = account.number },
			{ name = 'Card', value = TbUtils.MaskCardNumber(cardNumber) },
		})
	end

	return true, nil, cardId
end

--- A PIN that is too easy to guess: one repeated digit (1111), a run of
--- digits up and down (1234, 8765), a short block repeated (1212, 123123) or
--- anything containing an entry of Config.Cards.DenylistedPins.
---@param pin string
---@return boolean weak
function TbCards.IsWeakPin(pin)
	if pin:match('^(%d)%1+$') then
		return true
	end

	for size = 2, math.floor(#pin / 2) do
		if #pin % size == 0 and pin == pin:sub(1, size):rep(#pin / size) then
			return true
		end
	end

	-- a straight run of four or more digits in either direction
	local run, direction = 1, 0

	for i = 2, #pin do
		local step = tonumber(pin:sub(i, i)) - tonumber(pin:sub(i - 1, i - 1))

		if (step == 1 or step == -1) and (direction == 0 or step == direction) then
			direction = step
			run = run + 1
		else
			direction = (step == 1 or step == -1) and step or 0
			run = direction == 0 and 1 or 2
		end

		if run >= 4 then
			return true
		end
	end

	for _, denylisted in ipairs(Config.Cards.DenylistedPins) do
		if pin:find(denylisted, 1, true) then
			return true
		end
	end

	return false
end

--- Sets (or changes) the PIN on one of the holder's own cards.
---@param identifier string
---@param cardId integer
---@param pin string
---@return boolean ok
---@return string? errorReason
function TbCards.SetPin(identifier, cardId, pin)
	if not Config.Cards.Enabled then
		return false, 'card_disabled'
	end

	if type(pin) ~= 'string' then
		return false, 'card_invalid_length'
	end

	local card = GetCardById(cardId)

	if not card or card.holder_identifier ~= identifier or card.status == 'lost' then
		return false, 'card_no_card'
	end

	if #pin < Config.Cards.MinPinLength or #pin > Config.Cards.MaxPinLength or not pin:match('^%d+$') then
		return false, 'card_invalid_length'
	end

	if not Config.Cards.AllowWeakPins and TbCards.IsWeakPin(pin) then
		return false, 'card_too_weak'
	end

	local salt = TbUtils.RandomHex(16)
	local hash = TbSha256(salt .. pin)

	TbDb.Update('UPDATE tb_cards SET pin_hash = ?, pin_salt = ?, failed_pin_attempts = 0 WHERE id = ?', { hash, salt, card.id })

	return true, nil
end

--- Verifies a PIN against one specific card. Tracks failed attempts and
--- blocks the card after Config.Atm.PinLockoutAttempts, firing a security
--- webhook. A self-service lock fails this too, reported distinctly.
---@param identifier string
---@param cardId integer
---@param pin string
---@return boolean ok
---@return string? errorReason
---@return integer? accountId Only on success.
function TbCards.VerifyPin(identifier, cardId, pin)
	if not Config.Cards.Enabled then
		return false, 'card_disabled'
	end

	local card = GetCardById(cardId)

	if not card or card.holder_identifier ~= identifier or card.status == 'lost' then
		return false, 'atm_no_card'
	end

	if TbUtils.ToBool(card.is_locked) then
		return false, 'atm_card_locked'
	end

	if card.status == 'blocked' then
		return false, 'atm_card_blocked'
	end

	if not card.pin_hash or not card.pin_salt then
		return false, 'atm_no_pin_set'
	end

	-- Never hash something that cannot be a PIN, the NUI sends whatever it likes.
	if type(pin) ~= 'string' or #pin > math.max(Config.Cards.MaxPinLength, 8) then
		return false, 'atm_wrong_pin'
	end

	if TbSha256(card.pin_salt .. pin) ~= card.pin_hash then
		local attempts = (tonumber(card.failed_pin_attempts) or 0) + 1

		-- Counted in SQL so parallel guesses cannot all read the same old
		-- value. The status is assigned first, MySQL evaluates SET left to right.
		TbDb.Update(
			"UPDATE tb_cards SET status = CASE WHEN failed_pin_attempts + 1 >= ? THEN 'blocked' ELSE status END, failed_pin_attempts = failed_pin_attempts + 1 WHERE id = ?",
			{ Config.Atm.PinLockoutAttempts, card.id }
		)

		if attempts >= Config.Atm.PinLockoutAttempts then

			if TbLog then
				TbLog('security_alerts', 'Bank card blocked after failed PIN attempts', {
					{ name = 'Holder', value = identifier },
					{ name = 'Card', value = TbUtils.MaskCardNumber(card.number) },
					{ name = 'Attempts', value = tostring(attempts) },
				}, Config.Logs.Colors.danger)
			end

			return false, 'atm_card_blocked'
		end

		return false, 'atm_wrong_pin'
	end

	TbDb.Update('UPDATE tb_cards SET failed_pin_attempts = 0 WHERE id = ?', { card.id })
	return true, nil, card.account_id
end

--- A card usable for ATM actions right now: held by `identifier`, active,
--- not locked. The per-action re-check after the PIN gate opened the
--- session, so locking or blocking a card mid-session takes effect on the
--- next action, not the next visit.
---@param identifier string
---@param cardId integer
---@return table? row
---@return string? errorReason
function TbCards.GetUsable(identifier, cardId)
	local card = GetCardById(cardId)

	if not card or card.holder_identifier ~= identifier or card.status == 'lost' then
		return nil, 'atm_no_card'
	end

	if TbUtils.ToBool(card.is_locked) then
		return nil, 'atm_card_locked'
	end

	if card.status == 'blocked' then
		return nil, 'atm_card_blocked'
	end

	return card, nil
end

--- Toggles a card's self-service lock. Deliberately needs no PIN,
--- possession of the item is authority enough to freeze/unfreeze it, which
--- is what keeps a locked card from stranding its own holder behind a PIN
--- prompt they can't reach.
---@param identifier string
---@param cardId integer
---@return boolean ok
---@return string? errorReason
---@return boolean? isLocked New state, only on success.
function TbCards.ToggleLock(identifier, cardId)
	local card = GetCardById(cardId)

	if not card or card.holder_identifier ~= identifier or card.status ~= 'active' then
		return false, 'card_no_card'
	end

	local newLocked = TbUtils.ToBool(card.is_locked) and 0 or 1
	TbDb.Update('UPDATE tb_cards SET is_locked = ? WHERE id = ?', { newLocked, cardId })

	return true, nil, newLocked == 1
end

--- Reports a card lost: retires it, removes the item if still present,
--- charges the replacement fee from the card's account (a company's card is
--- paid for by the company) and issues a replacement.
---@param source integer
---@param identifier string
---@param cardId integer
---@return boolean ok
---@return string? errorReason
---@return integer? newCardId
function TbCards.ReportLost(source, identifier, cardId)
	if not Config.Cards.Enabled then
		return false, 'card_disabled'
	end

	local card = GetCardById(cardId)

	if not card or card.holder_identifier ~= identifier or card.status == 'lost' then
		return false, 'card_no_card'
	end

	if Config.Cards.ReplacementFee > 0 then
		local paid = TbAccounts.Debit(card.account_id, Config.Cards.ReplacementFee, TbEnums.TransactionType.ACCOUNT_FEE, identifier, 'Card replacement fee')

		if not paid then
			return false, 'card_insufficient_funds'
		end
	end

	TbDb.Update("UPDATE tb_cards SET status = 'lost' WHERE id = ?", { card.id })

	if card.inventory_serial then
		TbInventoryProvider.RemoveItem(source, Config.Cards.ItemName, card.inventory_serial)
	end

	return TbCards.Request(source, identifier, card.account_id)
end

--- Destroys a card the holder no longer wants: the row goes, the physical
--- item goes with it, and the account can be given a fresh card afterwards.
--- Distinct from ReportLost, which charges a fee and immediately reissues,
--- this one is free and leaves the player with no card for that account.
---@param source integer
---@param identifier string
---@param cardId integer
---@return boolean ok
---@return string? errorReason
function TbCards.Delete(source, identifier, cardId)
	if not Config.Cards.Enabled then
		return false, 'card_disabled'
	end

	local card = GetCardById(cardId)

	if not card or card.holder_identifier ~= identifier then
		return false, 'card_no_card'
	end

	if card.inventory_serial then
		TbInventoryProvider.RemoveItem(source, Config.Cards.ItemName, card.inventory_serial)
	end

	local ok, affected = TbDb.Update('DELETE FROM tb_cards WHERE id = ? AND holder_identifier = ?', { card.id, identifier })

	if ok and affected > 0 and TbLog then
		TbLog('cards', 'Card deleted', {
			{ name = 'Holder', value = identifier },
			{ name = 'Account', value = tostring(card.account_id) },
			{ name = 'Card', value = TbUtils.MaskCardNumber(card.number) },
		})
	end

	return ok and affected > 0, nil
end

-- Client-facing callbacks --------------------------------------------------

TbSafe.Callback('tiltann_banking:cards:list', function(source)
	local identifier = TbFramework.GetIdentifier(source)
	return identifier and TbCards.ListForHolder(identifier) or {}
end)

TbSafe.Callback('tiltann_banking:cards:request', function(source, accountId)
	local identifier = TbFramework.GetIdentifier(source)

	if not identifier then
		return false, 'card_no_card'
	end

	return TbCards.Request(source, identifier, tonumber(accountId) or 0)
end)

TbSafe.Callback('tiltann_banking:cards:setPin', function(source, cardId, pin)
	local identifier = TbFramework.GetIdentifier(source)

	if not identifier then
		return false, 'card_no_card'
	end

	return TbCards.SetPin(identifier, tonumber(cardId) or 0, tostring(pin))
end)

TbSafe.Callback('tiltann_banking:cards:toggleLock', function(source, cardId)
	local identifier = TbFramework.GetIdentifier(source)

	if not identifier then
		return false, 'card_no_card'
	end

	return TbCards.ToggleLock(identifier, tonumber(cardId) or 0)
end)

TbSafe.Callback('tiltann_banking:cards:delete', function(source, cardId)
	local identifier = TbFramework.GetIdentifier(source)

	if not identifier then
		return false, 'card_no_card'
	end

	return TbCards.Delete(source, identifier, tonumber(cardId) or 0)
end)

TbSafe.Callback('tiltann_banking:cards:reportLost', function(source, cardId)
	local identifier = TbFramework.GetIdentifier(source)

	if not identifier then
		return false, 'card_no_card'
	end

	return TbCards.ReportLost(source, identifier, tonumber(cardId) or 0)
end)
