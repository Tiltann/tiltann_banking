--- @module server.loans.loans
--- Personal financing. A loan is issued to, and repaid from, the borrower's
--- DEFAULT account. A true no-op when Config.Loans.Enabled is false: every
--- public function checks it first and the repayment tick never starts.

TbLoans = {}

---@param identifier string
---@return table? row
local function GetActiveLoanRow(identifier)
	local ok, row = TbDb.SelectOne("SELECT * FROM tb_loans WHERE borrower_identifier = ? AND status = 'active'", { identifier })

	if not ok then
		return nil
	end

	return row
end

---@param row table
---@return TbLoan
local function RowToLoan(row)
	return {
		id = row.id,
		accountId = row.account_id,
		principal = row.principal,
		interestRate = tonumber(row.interest_rate),
		totalOwed = row.total_owed,
		remainingBalance = row.remaining_balance,
		installmentAmount = row.installment_amount,
		installmentIntervalSeconds = row.installment_interval_seconds,
		nextPaymentDue = row.next_payment_due,
		missedPayments = row.missed_payments,
		autoPay = TbUtils.ToBool(row.auto_pay),
		status = row.status,
	}
end

--- The borrower's active loan, if any (one at a time).
---@param identifier string
---@return TbLoan?
function TbLoans.GetActive(identifier)
	local row = GetActiveLoanRow(identifier)
	return row and RowToLoan(row) or nil
end

--- Issues a loan, disbursing the principal to the default account.
---@param identifier string
---@param amount integer
---@return boolean ok
---@return string? errorReason
function TbLoans.RequestLoan(identifier, amount)
	if not Config.Loans.Enabled then
		return false, 'loan_disabled'
	end

	amount = TbUtils.RoundMoney(amount)

	if amount <= 0 or amount > Config.Loans.MaxLoanAmount then
		return false, 'loan_amount_too_high'
	end

	if amount < (Config.Loans.MinLoanAmount or 0) then
		return false, 'loan_amount_too_low'
	end

	if GetActiveLoanRow(identifier) then
		return false, 'loan_already_active'
	end

	local account = TbAccounts.GetOrCreateDefault(identifier)

	if not account then
		return false, 'account_not_found'
	end

	local totalOwed = TbUtils.RoundMoney(amount * (1 + Config.Loans.InterestRate / 100))
	local installmentAmount = TbUtils.RoundMoney(totalOwed / Config.Loans.InstallmentCount)
	local nextPaymentDue = os.date('!%Y-%m-%d %H:%M:%S', os.time() + Config.Loans.InstallmentIntervalSeconds)

	local insertOk, loanId = TbDb.Insert(
		[[INSERT INTO tb_loans
			(account_id, borrower_identifier, principal, interest_rate, total_owed, remaining_balance,
			 installment_amount, installment_interval_seconds, next_payment_due, auto_pay)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1)]],
		{
			account.id, identifier, amount, Config.Loans.InterestRate, totalOwed, totalOwed,
			installmentAmount, Config.Loans.InstallmentIntervalSeconds, nextPaymentDue,
		}
	)

	if not insertOk or not loanId then
		return false, 'account_not_found'
	end

	local credited = TbAccounts.Credit(account.id, amount, TbEnums.TransactionType.LOAN_DISBURSEMENT, identifier,
		('Loan #%d disbursed'):format(loanId), { loanId = loanId })

	if not credited then
		-- No money reached the account, so there must be no debt either.
		TbLogger.Error('loans', 'loan disbursement failed, loan removed', { loan = loanId, account = account.id, amount = amount })
		TbDb.Update('DELETE FROM tb_loans WHERE id = ?', { loanId })
		return false, 'account_not_found'
	end

	if TbLog then
		TbLog('loans', 'Loan issued', {
			{ name = 'Borrower', value = identifier },
			{ name = 'Principal', value = tostring(amount) },
			{ name = 'Total owed', value = tostring(totalOwed) },
		})
	end

	return true, nil
end

--- Records one payment and closes the loan once nothing remains.
---@param loan table Raw tb_loans row.
---@param amount integer
---@param isAutomatic boolean
local function RecordPayment(loan, amount, isAutomatic)
	local newRemaining = math.max(0, loan.remaining_balance - amount)

	TbDb.Update('UPDATE tb_loans SET remaining_balance = ? WHERE id = ?', { newRemaining, loan.id })
	TbDb.Insert('INSERT INTO tb_loan_payments (loan_id, amount, is_automatic) VALUES (?, ?, ?)', { loan.id, amount, isAutomatic })

	if newRemaining <= 0 then
		TbDb.Update("UPDATE tb_loans SET status = 'paid_off', closed_at = NOW() WHERE id = ?", { loan.id })
	else
		local nextDue = os.date('!%Y-%m-%d %H:%M:%S', os.time() + loan.installment_interval_seconds)
		TbDb.Update('UPDATE tb_loans SET next_payment_due = ? WHERE id = ?', { nextDue, loan.id })
	end
end

--- Manual (early) repayment from the default account.
---@param identifier string
---@param amount integer
---@return boolean ok
---@return string? errorReason
function TbLoans.RepayEarly(identifier, amount)
	if not Config.Loans.Enabled then
		return false, 'loan_disabled'
	end

	local loan = GetActiveLoanRow(identifier)

	if not loan then
		return false, 'loan_no_active_loan'
	end

	amount = TbUtils.RoundMoney(amount)

	if amount <= 0 then
		return false, 'tx_invalid_amount'
	end

	local payAmount = math.min(amount, loan.remaining_balance)
	local account = TbAccounts.GetOrCreateDefault(identifier)

	if not account then
		return false, 'account_not_found'
	end

	local ok = TbAccounts.Debit(account.id, payAmount, TbEnums.TransactionType.LOAN_REPAYMENT, identifier,
		('Loan #%d repayment'):format(loan.id), { loanId = loan.id })

	if not ok then
		return false, 'tx_insufficient_funds'
	end

	RecordPayment(loan, payAmount, false)

	if TbLog then
		TbLog('loans', 'Loan repaid', {
			{ name = 'Borrower', value = identifier },
			{ name = 'Amount', value = tostring(payAmount) },
		})
	end

	return true, nil
end

--- Handles one due loan. Run on its own so one bad row cannot stop the rest.
---@param loan table Raw tb_loans row.
local function ProcessDueLoan(loan)
	local account = TbAccounts.GetById(loan.account_id) or TbAccounts.GetDefaultForPlayer(loan.borrower_identifier)
	local paid = false

	if account then
		local installment = math.min(loan.installment_amount, loan.remaining_balance)

		if TbUtils.ToBool(loan.auto_pay) and account.balance >= installment then
			paid = TbAccounts.Debit(account.id, installment, TbEnums.TransactionType.LOAN_REPAYMENT, nil,
				('Automatic loan #%d installment'):format(loan.id), { loanId = loan.id })

			if paid then
				RecordPayment(loan, installment, true)
			end
		end
	end

	if not paid then
		local missed = loan.missed_payments + 1
		TbDb.Insert('INSERT INTO tb_loan_payments (loan_id, amount, missed) VALUES (?, 0, 1)', { loan.id })

		if missed >= Config.Loans.MaxMissedPayments then
			TbDb.Update("UPDATE tb_loans SET status = 'defaulted', missed_payments = ? WHERE id = ?", { missed, loan.id })

			if TbLog then
				TbLog('loans', 'Loan defaulted', {
					{ name = 'Loan', value = tostring(loan.id) },
					{ name = 'Borrower', value = loan.borrower_identifier },
					{ name = 'Missed payments', value = tostring(missed) },
				}, Config.Logs.Colors.danger)
			end
		else
			local nextDue = os.date('!%Y-%m-%d %H:%M:%S', os.time() + loan.installment_interval_seconds)
			TbDb.Update('UPDATE tb_loans SET missed_payments = ?, next_payment_due = ? WHERE id = ?', { missed, nextDue, loan.id })
		end
	end
end

--- One tick: every due loan is auto-debited (if auto_pay and affordable) or
--- marked missed, defaulting after Config.Loans.MaxMissedPayments.
local function RunRepaymentTick()
	local ok, dueLoans = TbDb.SelectMany("SELECT * FROM tb_loans WHERE status = 'active' AND next_payment_due <= NOW()")

	if not ok then
		return
	end

	for _, loan in ipairs(dueLoans) do
		TbSafe.Run('loans:installment', ProcessDueLoan, loan)
	end
end

local tickThreadStarted = false

--- Starts the repayment thread; only loops when Config.Loans.Enabled.
function TbLoans.StartRepaymentTick()
	if tickThreadStarted or not Config.Loans.Enabled then
		return
	end

	tickThreadStarted = true

	CreateThread(function()
		while true do
			Wait(Config.Loans.CheckIntervalMs)
			TbSafe.Run('loans:repayment', RunRepaymentTick)
		end
	end)
end

TbSafe.Callback('tiltann_banking:loans:getActive', function(source)
	local identifier = TbFramework.GetIdentifier(source)
	return identifier and TbLoans.GetActive(identifier) or nil
end)

TbSafe.Callback('tiltann_banking:loans:request', function(source, amount)
	local identifier = TbFramework.GetIdentifier(source)

	if not identifier then
		return false, 'loan_disabled'
	end

	return TbLoans.RequestLoan(identifier, tonumber(amount) or 0)
end)

TbSafe.Callback('tiltann_banking:loans:repay', function(source, amount)
	local identifier = TbFramework.GetIdentifier(source)

	if not identifier then
		return false, 'loan_disabled'
	end

	return TbLoans.RepayEarly(identifier, tonumber(amount) or 0)
end)

--- A borrower's finished loans, newest first: what they took, what it cost
--- in total, how it ended and when. `closed_at` is NULL for loans that were
--- closed before that column existed, so the last recorded payment stands in
--- for the date rather than showing nothing at all.
---@param identifier string
---@param limit integer?
---@return table[] loans
function TbLoans.ListHistory(identifier, limit)
	local ok, rows = TbDb.SelectMany(
		[[SELECT l.id, l.principal, l.interest_rate, l.total_owed, l.status, l.created_at,
				COALESCE(l.closed_at, (SELECT MAX(p.created_at) FROM tb_loan_payments p WHERE p.loan_id = l.id)) AS closed_at
			FROM tb_loans l
			WHERE l.borrower_identifier = ? AND l.status <> 'active'
			ORDER BY l.id DESC
			LIMIT ?]],
		{ identifier, limit or 10 }
	)

	if not ok then
		return {}
	end

	local history = {}

	for i, row in ipairs(rows) do
		history[i] = {
			id = row.id,
			principal = row.principal,
			interestRate = tonumber(row.interest_rate) or 0,
			totalOwed = row.total_owed,
			status = row.status,
			createdAt = row.created_at,
			closedAt = row.closed_at,
		}
	end

	return history
end
