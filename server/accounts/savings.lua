--- @module server.accounts.savings
--- Interest tick for savings accounts. Every Config.Savings.IntervalSeconds
--- each live savings account with at least MinBalanceForInterest earns
--- `balance * interest_rate%`, capped at MaxInterestPerTick, recorded as an
--- `interest` transaction. A true no-op when Config.Savings.Enabled is false:
--- the thread never starts.

TbSavings = {}

--- Pays (or skips) one account. Run on its own so one bad row cannot stop the rest.
---@param row table
local function PayInterest(row)
	local claimOk, claimed = TbDb.Update(
		[[UPDATE tb_accounts SET last_interest_at = NOW()
			WHERE id = ? AND (last_interest_at IS NULL OR last_interest_at <= DATE_SUB(NOW(), INTERVAL ? SECOND))]],
		{ row.id, Config.Savings.IntervalSeconds }
	)

	if claimOk and claimed > 0 then
		local rate = tonumber(row.interest_rate) or Config.Savings.InterestRate
		local interest = math.min(TbUtils.RoundMoney(row.balance * (rate / 100)), Config.Savings.MaxInterestPerTick)

		if interest > 0 then
			TbAccounts.Credit(row.id, interest, TbEnums.TransactionType.INTEREST, nil, ('%.3f%% interest'):format(rate))
		end
	end
end

--- One pass: credit every savings account whose interval has elapsed.
--- last_interest_at is bumped in the same statement that picks the rows, so
--- two overlapping ticks can't pay the same interval twice.
local function RunInterestTick()
	local ok, rows = TbDb.SelectMany(
		[[SELECT id, balance, interest_rate FROM tb_accounts
			WHERE type = 'savings' AND deleted_at IS NULL AND balance >= ?
				AND (last_interest_at IS NULL OR last_interest_at <= DATE_SUB(NOW(), INTERVAL ? SECOND))]],
		{ Config.Savings.MinBalanceForInterest, Config.Savings.IntervalSeconds }
	)

	if not ok then
		return
	end

	for _, row in ipairs(rows) do
		TbSafe.Run('savings:account', PayInterest, row)
	end
end

local tickStarted = false

--- Starts the interest thread. Called once from server/main.lua; only
--- actually loops when Config.Savings.Enabled is true.
function TbSavings.StartInterestTick()
	if tickStarted or not Config.Savings.Enabled then
		return
	end

	tickStarted = true

	CreateThread(function()
		while true do
			Wait(Config.Savings.CheckIntervalMs)
			TbSafe.Run('savings:interest', RunInterestTick)
		end
	end)
end
