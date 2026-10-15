import type { Translations } from './i18n/strings';
import type { SqlDateTime } from "./format";

// Mirrors the Lua-side shapes in shared/enums.lua and the server/terminal,
// server/atm and server/cards callbacks. Kept in sync by hand, there's no
// cross-language codegen, just the two matching definitions.

export interface TbUiColors {
	primary: string;
	secondary: string;
	accent: string;
	background: string;
	surface: string;
	textPrimary: string;
	textMuted: string;
	success: string;
	danger: string;
	warning: string;
}

export type TbAccountType = 'personal' | 'savings' | 'society';
export type TbRole = 'owner' | 'admin' | 'contributor';

export interface TbAccount {
	id: number;
	type: TbAccountType;
	ownerIdentifier: string | null;
	jobName: string | null;
	/** Human-facing job name ("Polizei"), resolved from ESX. Show this, never jobName. */
	jobLabel?: string | null;
	number: string;
	name: string;
	balance: number;
	isDefault: boolean;
	isTreasury: boolean;
	interestRate: number | null;
	/** Savings only: SQL datetime until which nothing may leave the account. */
	lockedUntil: SqlDateTime;
	/** Rows up to this moment are hidden from the statement (soft clear). */
	historyClearedAt?: SqlDateTime;
	createdAt: SqlDateTime;
}

export interface TbCapabilities {
	view: boolean;
	deposit: boolean;
	withdraw: boolean;
	manageStaff: boolean;
	invoice: boolean;
	delete: boolean;
}

export type TbTransactionType =
	| 'deposit'
	| 'withdraw'
	| 'transfer'
	| 'tax'
	| 'interest'
	| 'standing_order'
	| 'loan_disbursement'
	| 'loan_repayment'
	| 'invoice_payment'
	| 'account_fee'
	| 'admin_adjustment'
	| 'sync_correction';

export interface TbTransaction {
	id: number;
	fromAccountId: number | null;
	toAccountId: number | null;
	type: TbTransactionType;
	amount: number;
	balanceAfter: number;
	actorIdentifier: string | null;
	note: string | null;
	metadata: Record<string, unknown> | null;
	createdAt: SqlDateTime;
}

export interface TbTransactionFilters {
	type?: TbTransactionType;
	minAmount?: number;
	maxAmount?: number;
	from?: string;
	to?: string;
}

export interface TbWeekPoint {
	day: string;
	income: number;
	expenses: number;
}

export interface TbDailyTotals {
	day: string;
	deposits: number;
	withdrawals: number;
	adminAdjustments: number;
}

export interface TbLoan {
	id: number;
	accountId: number;
	principal: number;
	interestRate: number;
	totalOwed: number;
	remainingBalance: number;
	installmentAmount: number;
	installmentIntervalSeconds: number;
	nextPaymentDue: SqlDateTime;
	missedPayments: number;
	autoPay: boolean;
	status: 'active' | 'paid_off' | 'defaulted' | 'cancelled';
}

export interface TbInvoiceView {
	id: number;
	amount: number;
	reason: string | null;
	status: 'pending' | 'paid' | 'declined' | 'overdue' | 'cancelled';
	dueAt: SqlDateTime;
	createdAt: SqlDateTime;
	counterpartyName: string;
	counterpartyNumber: string;
	counterpartyPerson?: string | null;
	direction: 'incoming' | 'outgoing';
	/** Bills from a person can be declined, bills from a business cannot. */
	canDecline?: boolean;
	resolvedAt?: SqlDateTime;
}

export interface TbStandingOrder {
	id: number;
	fromAccountId: number;
	toAccountNumber: string;
	toName: string | null;
	amount: number;
	intervalSeconds: number;
	nextRunAt: SqlDateTime;
	note: string | null;
	active: boolean;
	failedRuns: number;
}

export interface TbCardSummary {
	id: number;
	accountId: number;
	accountName: string;
	accountNumber: string;
	isCompany: boolean;
	maskedNumber: string;
	status: 'active' | 'blocked';
	isLocked: boolean;
	hasPin: boolean;
}

export interface TbBusinessSummary {
	accountId: number;
	name: string;
	number: string;
	jobName: string | null;
	jobLabel: string | null;
	role: TbRole;
	capabilities: TbCapabilities;
}

export interface TbGradeRole {
	grade: number;
	label: string;
	role: TbRole;
	/** Pinned to owner by Config.Society.HighestGradeIsOwner, not editable. */
	isHighest: boolean;
}

/** server/society/members.lua listGradeRoles */
export interface TbGradeRoleView {
	allowed: boolean;
	jobName?: string | null;
	jobLabel?: string | null;
	highestIsOwner?: boolean;
	grades?: TbGradeRole[];
	capabilities?: Record<TbRole, TbCapabilities>;
}

/** A finished loan, for the history list on the Loans page. */
export interface TbLoanHistoryEntry {
	id: number;
	principal: number;
	interestRate: number;
	totalOwed: number;
	status: 'paid_off' | 'defaulted' | 'cancelled';
	createdAt: SqlDateTime;
	closedAt: SqlDateTime;
}

export interface TbStaffMember {
	identifier: string;
	/** RP name captured when they were added; null for rows created before that was stored. */
	name: string | null;
	/** Their current server id while connected, else null, the number a manager can actually act on. */
	serverId?: number | null;
	role: TbRole;
	cardDailyLimit: number | null;
}

export interface TbFeatureToggles {
	cardsEnabled: boolean;
	savingsEnabled: boolean;
	loansEnabled: boolean;
	billingEnabled: boolean;
	standingOrdersEnabled: boolean;
	taxEnabled: boolean;
	clearHistoryEnabled: boolean;
}

export type TbTaxKind = 'deposit' | 'withdraw' | 'transfer' | 'periodic';

export interface TbTaxRecord {
	id: number;
	accountId: number;
	accountName: string;
	taxableAmount: number;
	taxAmount: number;
	rate: number;
	kind: TbTaxKind;
	createdAt: SqlDateTime;
}

/** server/tax/tax.lua getOverview */
export interface TbTaxOverview {
	enabled: boolean;
	mode?: 'flat' | 'bracket';
	flatRate?: number;
	brackets?: { min: number; max: number | null; rate: number }[];
	minTaxableAmount?: number;
	appliesOn?: TbTaxKind[];
	periodic?: { rate: number; intervalSeconds: number } | null;
	destinationType?: 'society' | 'account' | 'burn';
	destinationName?: string | null;
	totalPaid?: number;
	/** Config.Tax.SummaryPeriodDays */
	periodDays?: number;
	paidInPeriod?: number;
	records?: TbTaxRecord[];
}

/** server/terminal/personal.lua getPersonal */
export interface TbPersonalOverview {
	allowed: boolean;
	accounts: TbAccount[];
	totalBalance: number;
	week: TbWeekPoint[];
	latestTransactions: TbTransaction[];
	openInvoices: TbInvoiceView[];
	loan: TbLoan | null;
	loanHistory: TbLoanHistoryEntry[];
	cards: TbCardSummary[];
	standingOrders: TbStandingOrder[];
	limits: {
		maxAccounts: number;
		newAccountPrice: number;
		maxSavings: number;
		savingsPrice: number;
		savingsRate: number;
		savingsLockSeconds: number;
		/** Seconds between two interest payouts. */
		savingsIntervalSeconds: number;
		/** 0..1, share of the opening fee that is credited to the new account. */
		feeToBalance: number;
		maxLoan: number;
		minLoan: number;
		loanPresets: number[];
		minOrderInterval: number;
	};
}

/** server/terminal/business.lua getBusiness */
export interface TbBusinessView {
	allowed: boolean;
	account?: TbAccount;
	role?: TbRole;
	capabilities?: TbCapabilities;
	days?: TbDailyTotals[];
	latestTransactions?: TbTransaction[];
	openInvoices?: { incoming: TbInvoiceView[]; outgoing: TbInvoiceView[] };
	standingOrders?: TbStandingOrder[];
	card?: TbCardSummary | null;
	canHoldCard?: boolean;
}

/** server/atm/atm.lua open */
export interface TbAtmOpenData {
	cardsEnabled: boolean;
	cards: TbCardSummary[];
	accounts: TbAccount[];
}

/** server/atm/atm.lua unlock / getSession */
export interface TbAtmSession {
	cardId: number | null;
	account: TbAccount;
	isCompany: boolean;
	dailyLimit: number;
	withdrawnToday: number;
	quickWithdraw: number[];
}

/** Which card/account an ATM action is keyed by, see server/atm/atm.lua ResolveTarget. */
export interface TbAtmKey {
	cardId?: number;
	accountId?: number;
}

interface BankUiOpenBase {
	action: 'open';
	colors: TbUiColors;
	currencySymbol: string;
	defaultLanguage: string;
	/** locales/ui/*.json, sent by the game when the UI opens. */
	translations: Translations;
	features: TbFeatureToggles;
}

export interface AtmOpenPayload extends BankUiOpenBase {
	mode: 'atm';
	atm: TbAtmOpenData;
}

export interface TerminalOpenPayload extends BankUiOpenBase {
	mode: 'terminal';
	personal: TbPersonalOverview;
	businesses: TbBusinessSummary[];
	business: TbBusinessView | null;
}

export interface BillingOpenPayload extends BankUiOpenBase {
	mode: 'billing';
	/** Accounts the player may bill from or pay with (personal and business). */
	accounts: TbAccount[];
	billing: { maxSharePercent: number; nearbyRadius: number };
}

export type BankUiOpenPayload = AtmOpenPayload | TerminalOpenPayload | BillingOpenPayload;

export interface BankUiClosePayload {
	action: 'close';
}

export interface BankUiRefreshPayload {
	action: 'refresh';
}

export type BankUiMessage = BankUiOpenPayload | BankUiClosePayload | BankUiRefreshPayload;

/** Every mutating NUI callback resolves to this (see client/ui/bank_ui.lua ForwardAction). */
export interface ActionResult<T = unknown> {
	ok: boolean;
	errorKey?: string;
	value?: T;
}
