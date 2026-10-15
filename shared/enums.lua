--- @module shared.enums
--- Shared string constants and row-shape type annotations, referenced from
--- both client and server code so every module describes the same database
--- rows the same way instead of re-documenting columns in prose.

---@alias TbAccountType
---| 'personal'
---| 'savings'
---| 'society'

---@alias TbTransactionType
---| 'deposit'
---| 'withdraw'
---| 'transfer'
---| 'tax'
---| 'interest'
---| 'standing_order'
---| 'loan_disbursement'
---| 'loan_repayment'
---| 'invoice_payment'
---| 'account_fee'
---| 'admin_adjustment'
---| 'sync_correction'

---@alias TbLoanStatus 'active'|'paid_off'|'defaulted'|'cancelled'
---@alias TbInvoiceStatus 'pending'|'paid'|'declined'|'overdue'|'cancelled'
---@alias TbCardStatus 'active'|'blocked'|'lost'

---@class TbAccount
---@field id integer
---@field type TbAccountType
---@field ownerIdentifier string? Player identifier for personal/savings rows; nil for a business.
---@field jobName string? ESX job a business is linked to; nil for personal rows and standalone businesses.
---@field number string Cosmetic account number, '<clearing>-<8 digits>'.
---@field name string
---@field balance integer Whole units of the server currency.
---@field isDefault boolean
---@field isTreasury boolean
---@field interestRate number? Savings only.
---@field lockedUntil string? Savings only, SQL datetime until which nothing may leave the account (Config.Savings.WithdrawLockSeconds).
---@field historyClearedAt string? SQL datetime, statements hide every transaction up to this moment (soft clear, rows stay in tb_transactions).
---@field createdAt string

---@class TbTransaction
---@field id integer
---@field fromAccountId integer?
---@field toAccountId integer?
---@field type TbTransactionType
---@field amount integer
---@field balanceAfter integer
---@field actorIdentifier string?
---@field note string?
---@field metadata table?
---@field createdAt string

---@class TbCard
---@field id integer
---@field accountId integer
---@field holderIdentifier string
---@field number string
---@field status TbCardStatus
---@field isLocked boolean
---@field hasPin boolean
---@field failedPinAttempts integer
---@field inventorySerial string?

---@class TbLoan
---@field id integer
---@field accountId integer
---@field principal integer
---@field interestRate number
---@field totalOwed integer
---@field remainingBalance integer
---@field installmentAmount integer
---@field installmentIntervalSeconds integer
---@field nextPaymentDue string
---@field missedPayments integer
---@field autoPay boolean
---@field status TbLoanStatus

---@class TbInvoice
---@field id integer
---@field senderAccountId integer
---@field recipientAccountId integer
---@field amount integer
---@field reason string?
---@field status TbInvoiceStatus
---@field dueAt string?
---@field createdAt string

---@class TbStandingOrder
---@field id integer
---@field fromAccountId integer
---@field toAccountNumber string
---@field amount integer
---@field intervalSeconds integer
---@field nextRunAt string
---@field note string?
---@field active boolean
---@field failedRuns integer

---@class TbBusinessSummary
---@field accountId integer
---@field name string
---@field number string
---@field jobName string?
---@field role TbRole
---@field capabilities TbCapabilities

TbEnums = {
	AccountType = {
		PERSONAL = 'personal',
		SAVINGS = 'savings',
		SOCIETY = 'society',
	},
	Role = {
		OWNER = 'owner',
		ADMIN = 'admin',
		CONTRIBUTOR = 'contributor',
	},
	TransactionType = {
		DEPOSIT = 'deposit',
		WITHDRAW = 'withdraw',
		TRANSFER = 'transfer',
		TAX = 'tax',
		INTEREST = 'interest',
		STANDING_ORDER = 'standing_order',
		LOAN_DISBURSEMENT = 'loan_disbursement',
		LOAN_REPAYMENT = 'loan_repayment',
		INVOICE_PAYMENT = 'invoice_payment',
		ACCOUNT_FEE = 'account_fee',
		ADMIN_ADJUSTMENT = 'admin_adjustment',
		SYNC_CORRECTION = 'sync_correction',
	},
	CardStatus = {
		ACTIVE = 'active',
		BLOCKED = 'blocked',
		LOST = 'lost',
	},
	LoanStatus = {
		ACTIVE = 'active',
		PAID_OFF = 'paid_off',
		DEFAULTED = 'defaulted',
		CANCELLED = 'cancelled',
	},
	InvoiceStatus = {
		PENDING = 'pending',
		PAID = 'paid',
		DECLINED = 'declined',
		OVERDUE = 'overdue',
		CANCELLED = 'cancelled',
	},
}

--- A fully-denied capability set, returned wherever access can't be
--- established, callers never have to nil-check.
---@type TbCapabilities
TbEnums.NoCapabilities = { view = false, deposit = false, withdraw = false, manageStaff = false, invoice = false, delete = false }
