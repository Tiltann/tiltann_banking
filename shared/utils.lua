--- @module shared.utils
--- Pure helper functions usable from both client and server. Nothing in this
--- file touches the database, ESX, or any export, it's safe to call from
--- either side with identical behaviour.

TbUtils = {}

--- Rounds a signed amount to the nearest whole currency unit. Money is
--- stored and passed around as whole integers everywhere in this resource,
--- this is the one place that guards against a caller passing a float in.
--- Anything that is not a sane finite number (nil, a string, NaN, infinity)
--- becomes 0, which every caller already rejects as an invalid amount.
---@param amount any
---@return integer
function TbUtils.RoundMoney(amount)
	amount = tonumber(amount)

	if not amount or amount ~= amount or amount > 2 ^ 53 or amount < -(2 ^ 53) then
		return 0
	end

	if amount >= 0 then
		return math.floor(amount + 0.5)
	end

	return -math.floor(-amount + 0.5)
end

--- Random numeric string of the given length (card and account numbers).
--- Not cryptographically significant, collision-checked against the
--- database by the caller, not guaranteed unique by this function alone.
---@param length integer
---@return string
function TbUtils.RandomDigits(length)
	local digits = {}

	for i = 1, length do
		digits[i] = tostring(math.random(0, 9))
	end

	return table.concat(digits)
end

--- Random hex string of the given length (characters, not bytes), used as a
--- per-card PIN salt. math.random is adequate for salting a short PIN hash.
---@param length integer
---@return string
function TbUtils.RandomHex(length)
	local chars = {}
	local hexDigits = '0123456789abcdef'

	for i = 1, length do
		local index = math.random(1, #hexDigits)
		chars[i] = hexDigits:sub(index, index)
	end

	return table.concat(chars)
end

--- Account number in the '<clearing>-<8 digits>' shape players type when
--- transferring, e.g. '920-48271039'. Cosmetic, uniqueness is enforced by
--- tb_accounts.number's unique key and the caller's collision check.
---@return string
function TbUtils.GenerateAccountNumber()
	return ('%s-%s'):format(Config.Accounts.ClearingNumber, TbUtils.RandomDigits(8))
end

--- Formats a whole-number amount with the configured currency symbol.
---@param amount integer
---@return string
function TbUtils.FormatMoney(amount)
	amount = tonumber(amount) or 0
	local symbol = (Config and Config.UI and Config.UI.CurrencySymbol) or '$'
	local formatted = tostring(math.floor(amount))
	local sign = ''

	if formatted:sub(1, 1) == '-' then
		sign = '-'
		formatted = formatted:sub(2)
	end

	local withSeparators = formatted:reverse():gsub('(%d%d%d)', '%1,'):reverse()
	withSeparators = withSeparators:gsub('^,', '')

	return ('%s%s%s'):format(sign, symbol, withSeparators)
end

--- Masks a 16-digit card number for display, keeping the last 4 digits.
---@param cardNumber string
---@return string
function TbUtils.MaskCardNumber(cardNumber)
	cardNumber = tostring(cardNumber or '')
	local last4 = cardNumber:sub(-4)
	return ('\u{2022}\u{2022}\u{2022}\u{2022} \u{2022}\u{2022}\u{2022}\u{2022} \u{2022}\u{2022}\u{2022}\u{2022} %s'):format(last4)
end

--- Trims and length-caps a player-typed name (account names, notes).
---@param value any
---@param maxLength integer
---@return string? cleaned `nil` if not a usable non-empty string.
function TbUtils.CleanName(value, maxLength)
	if type(value) ~= 'string' then
		return nil
	end

	local cleaned = value:gsub('^%s+', ''):gsub('%s+$', '')

	if cleaned == '' then
		return nil
	end

	return cleaned:sub(1, maxLength)
end

--- Shallow table copy, hands a config table to a caller without letting
--- them mutate the shared Config.* original.
---@generic T : table
---@param source T
---@return T
function TbUtils.ShallowCopy(source)
	local copy = {}

	for key, value in pairs(source) do
		copy[key] = value
	end

	return copy
end

--- Normalises a database flag to a real boolean.
---
--- oxmysql maps MySQL's TINYINT(1) to a JavaScript boolean before the row
--- ever reaches Lua, so a column holding 1 arrives as `true` and the obvious
--- `row.is_locked == 1` is FALSE for a locked card. That mismatch silently
--- inverted every flag in this resource: a locked card reported itself
--- unlocked, the main account lost its marker, standing orders looked
--- inactive. Every flag read goes through here instead of comparing against
--- a literal. Also accepts the raw 1 / '1' a different driver, a manual
--- query or a future oxmysql setting would hand back.
---@param value any
---@return boolean
function TbUtils.ToBool(value)
	return value == true or value == 1 or value == '1'
end

--- Whether the ox_target path should be used for interactions, honouring
--- Config.Interaction.Mode. 'target' does NOT fall back when ox_target is
--- missing: a server that asked for target mode should notice it is not
--- installed, rather than silently getting a keybind it did not want.
---@return boolean
function TbUtils.UseOxTarget()
	local mode = (Config.Interaction and Config.Interaction.Mode) or 'auto'

	if mode == 'helpnotification' or mode == 'custom' then
		return false
	end

	if mode == 'target' then
		return true
	end

	return GetResourceState('ox_target') == 'started'
end

--- Waits (up to `timeoutMs`) for ox_target to be started. Needed because
--- 'target' mode never falls back: ox_target may simply start after this
--- resource, which is fine, but a server that never starts it should get a
--- clear log line instead of a Lua error from a missing export.
---@param timeoutMs integer?
---@return boolean started
function TbUtils.WaitForOxTarget(timeoutMs)
	local deadline = GetGameTimer() + (timeoutMs or 10000)

	while GetResourceState('ox_target') ~= 'started' do
		if GetGameTimer() >= deadline then
			return false
		end

		Wait(250)
	end

	return true
end
