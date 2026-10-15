--- @module server.tax.tax
--- "Steuern". TbTax.Apply is a true no-op when Config.Tax.Enabled is false,
--- the first line returns the gross amount unchanged with zero DB access, so
--- callers never need their own enabled-check. Collected tax lands wherever
--- Config.Tax.Destination points (a job's business account, a fixed account
--- number, or nowhere) and every collection is written to tb_tax_records,
--- which feeds the player's Tax page (tiltann_banking:tax:getOverview).

TbTax = {}

---@param amount integer
---@return number rate
---@return string? bracketLabel
local function ResolveRate(amount)
	if Config.Tax.Mode == 'flat' then
		return Config.Tax.FlatRate, nil
	end

	for _, bracket in ipairs(Config.Tax.Brackets) do
		if amount >= bracket.min and (bracket.max == nil or amount < bracket.max) then
			return bracket.rate, ('%s-%s'):format(bracket.min, bracket.max or '+')
		end
	end

	return 0, nil
end

--- The account tax is credited to, per Config.Tax.Destination. nil when the
--- destination is 'burn' or can't be resolved (then tax is only recorded).
---@return TbAccount?
function TbTax.GetTreasury()
	local destination = Config.Tax.Destination or {}

	if destination.Type == 'account' then
		return TbAccounts.GetByNumber(destination.AccountNumber or '')
	end

	if destination.Type ~= 'society' then
		return nil
	end

	local treasury = TbAccounts.GetOrCreateJobAccount(destination.Job or 'government', destination.Label or 'Treasury')

	if treasury and not treasury.isTreasury then
		TbDb.Update('UPDATE tb_accounts SET is_treasury = 1 WHERE id = ?', { treasury.id })
	end

	return treasury
end

--- Applies tax to a gross amount. Returns the net the caller should credit
--- (deposit / transfer) or hand out (withdraw).
---@param identifier string?
---@param accountId integer
---@param grossAmount integer
---@param kind 'deposit'|'withdraw'|'transfer'|'periodic'
---@param fixedRate number? Overrides Mode/FlatRate (used by the periodic tick).
---@return integer netAmount
---@return integer taxAmount
function TbTax.Apply(identifier, accountId, grossAmount, kind, fixedRate)
	if not Config.Tax.Enabled or (not fixedRate and not Config.Tax.ApplyOn[kind]) then
		return grossAmount, 0
	end

	if grossAmount < (Config.Tax.MinTaxableAmount or 0) then
		return grossAmount, 0
	end

	local rate, bracketLabel = fixedRate, nil

	if not rate then
		rate, bracketLabel = ResolveRate(grossAmount)
	end

	if rate <= 0 then
		return grossAmount, 0
	end

	local taxAmount = TbUtils.RoundMoney(grossAmount * (rate / 100))

	if taxAmount <= 0 then
		return grossAmount, 0
	end

	local treasury = TbTax.GetTreasury()

	if treasury then
		TbAccounts.Credit(treasury.id, taxAmount, TbEnums.TransactionType.TAX, identifier, ('%s tax from account #%d'):format(kind, accountId))
	end

	TbDb.Insert(
		[[INSERT INTO tb_tax_records (account_id, taxable_amount, tax_amount, rate_applied, bracket_label, treasury_account_id, kind)
			VALUES (?, ?, ?, ?, ?, ?, ?)]],
		{ accountId, grossAmount, taxAmount, rate, bracketLabel, treasury and treasury.id or nil, kind }
	)

	if TbLog then
		TbLog('tax', 'Tax collected', {
			{ name = 'Account', value = tostring(accountId) },
			{ name = 'Kind', value = kind },
			{ name = 'Gross', value = tostring(grossAmount) },
			{ name = 'Tax', value = tostring(taxAmount) },
			{ name = 'Rate', value = ('%.2f%%'):format(rate) },
		})
	end

	return grossAmount - taxAmount, taxAmount
end

--- Tax paid across every account a player owns, newest first.
---@param identifier string
---@param limit integer
---@return table[] records
function TbTax.ListForPlayer(identifier, limit)
	local ok, rows = TbDb.SelectMany(
		[[SELECT r.id, r.account_id, r.taxable_amount, r.tax_amount, r.rate_applied, r.kind, r.created_at, a.name AS account_name
			FROM tb_tax_records r
			JOIN tb_accounts a ON a.id = r.account_id
			WHERE a.owner_identifier = ?
			ORDER BY r.created_at DESC
			LIMIT ?]],
		{ identifier, limit }
	)

	if not ok then
		return {}
	end

	local records = {}

	for i, row in ipairs(rows) do
		records[i] = {
			id = row.id,
			accountId = row.account_id,
			accountName = row.account_name,
			taxableAmount = row.taxable_amount,
			taxAmount = row.tax_amount,
			rate = tonumber(row.rate_applied) or 0,
			kind = row.kind or 'deposit',
			createdAt = row.created_at,
		}
	end

	return records
end

--- Everything the Tax page shows: the rules in force, where money goes,
--- totals for this player, and their recent records.
TbSafe.Callback('tiltann_banking:tax:getOverview', function(source)
	local identifier = TbFramework.GetIdentifier(source)

	if not identifier or not Config.Tax.Enabled then
		return { enabled = false }
	end

	local periodDays = Config.Tax.SummaryPeriodDays or 30
	local ok, totals = TbDb.SelectOne(
		[[SELECT COALESCE(SUM(r.tax_amount), 0) AS total,
			COALESCE(SUM(CASE WHEN r.created_at >= DATE_SUB(NOW(), INTERVAL ? DAY) THEN r.tax_amount ELSE 0 END), 0) AS period
			FROM tb_tax_records r JOIN tb_accounts a ON a.id = r.account_id
			WHERE a.owner_identifier = ?]],
		{ periodDays, identifier }
	)

	local treasury = TbTax.GetTreasury()
	local destination = Config.Tax.Destination or {}
	local appliesOn = {}

	for _, kind in ipairs({ 'deposit', 'withdraw', 'transfer' }) do
		if Config.Tax.ApplyOn[kind] then
			appliesOn[#appliesOn + 1] = kind
		end
	end

	return {
		enabled = true,
		mode = Config.Tax.Mode,
		flatRate = Config.Tax.FlatRate,
		brackets = Config.Tax.Brackets,
		minTaxableAmount = Config.Tax.MinTaxableAmount or 0,
		appliesOn = appliesOn,
		periodic = Config.Tax.PeriodicBalanceTax.Enabled and {
			rate = Config.Tax.PeriodicBalanceTax.Rate,
			intervalSeconds = math.floor(Config.Tax.PeriodicBalanceTax.IntervalMs / 1000),
		} or nil,
		destinationType = destination.Type or 'burn',
		destinationName = treasury and treasury.name or nil,
		totalPaid = ok and totals and tonumber(totals.total) or 0,
		periodDays = periodDays,
		paidInPeriod = ok and totals and tonumber(totals.period) or 0,
		records = TbTax.ListForPlayer(identifier, 50),
	}
end)

local periodicTickStarted = false

--- Periodic balance tax on online players' main accounts only, see
--- Config.Tax.PeriodicBalanceTax for why offline taxation is not done.
local function RunPeriodicTick()
	for _, player in ipairs(TbFramework.GetPlayers()) do
		local account = TbAccounts.GetDefaultForPlayer(player.identifier)

		if account and account.balance > 0 then
			local _, taxAmount = TbTax.Apply(player.identifier, account.id, account.balance, 'periodic', Config.Tax.PeriodicBalanceTax.Rate)

			if taxAmount > 0 then
				TbAccounts.Debit(account.id, taxAmount, TbEnums.TransactionType.TAX, player.identifier, 'Periodic balance tax')
			end
		end
	end
end

--- Starts the periodic tax thread; only loops when both toggles are on.
function TbTax.StartPeriodicTick()
	if periodicTickStarted or not Config.Tax.Enabled or not Config.Tax.PeriodicBalanceTax.Enabled then
		return
	end

	periodicTickStarted = true

	CreateThread(function()
		while true do
			Wait(Config.Tax.PeriodicBalanceTax.IntervalMs)
			TbSafe.Run('tax:periodic', RunPeriodicTick)
		end
	end)
end
