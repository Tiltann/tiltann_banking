import type { Translations } from '../i18n/strings';
import type {
	AtmOpenPayload,
	BillingOpenPayload,
	TbAccount,
	TbAtmSession,
	TbBusinessView,
	TbCardSummary,
	TbPersonalOverview,
	TbStaffMember,
	TbTaxOverview,
	TbTransaction,
	TerminalOpenPayload,
} from '../types';

// Standalone-browser preview data (no live FiveM server on the build box).
// Realistic, messy numbers rather than round placeholders, used only when
// window.GetParentResourceName is absent. See api/nui.ts.

const COLORS = {
	primary: '#1c1f26',
	secondary: '#2a2e37',
	accent: '#4f8cff',
	background: '#111319',
	surface: '#1a1d24',
	textPrimary: '#f2f3f5',
	textMuted: '#8b909c',
	success: '#3ecf8e',
	danger: '#e5484d',
	warning: '#e5a83d',
};

const FEATURES = {
	cardsEnabled: true,
	savingsEnabled: true,
	loansEnabled: true,
	billingEnabled: true,
	standingOrdersEnabled: true,
	taxEnabled: true,
	clearHistoryEnabled: true,
};

export const MOCK_ACCOUNTS: TbAccount[] = [
	{ id: 91, type: 'personal', ownerIdentifier: 'char1:8f2a1c9d0b3e', jobName: null, number: '920-48271039', name: 'Main account', balance: 18420, isDefault: true, isTreasury: false, interestRate: null, lockedUntil: null, createdAt: '2026-01-14 08:03:00' },
	{ id: 94, type: 'personal', ownerIdentifier: 'char1:8f2a1c9d0b3e', jobName: null, number: '920-77103412', name: 'Car fund', balance: 6250, isDefault: false, isTreasury: false, interestRate: null, lockedUntil: null, createdAt: '2026-05-02 17:41:12' },
	{ id: 97, type: 'savings', ownerIdentifier: 'char1:8f2a1c9d0b3e', jobName: null, number: '920-30918827', name: 'Savings', balance: 41900, isDefault: false, isTreasury: false, interestRate: 1.5, lockedUntil: '2026-10-02 11:20:44', createdAt: '2026-06-19 11:20:44' },
];

export const MOCK_BUSINESS_ACCOUNT: TbAccount = {
	id: 4, type: 'society', ownerIdentifier: null, jobName: 'mechanic', number: '920-11223344', name: 'Bennys Original Motor Works', balance: 284730, isDefault: false, isTreasury: false, interestRate: null, lockedUntil: null, createdAt: '2026-06-02 14:21:09',
};

export const MOCK_CARDS: TbCardSummary[] = [
	{ id: 12, accountId: 91, accountName: 'Main account', accountNumber: '920-48271039', isCompany: false, maskedNumber: '•••• •••• •••• 4471', status: 'active', isLocked: false, hasPin: true },
	{ id: 13, accountId: 94, accountName: 'Car fund', accountNumber: '920-77103412', isCompany: false, maskedNumber: '•••• •••• •••• 0928', status: 'active', isLocked: true, hasPin: true },
	{ id: 18, accountId: 4, accountName: 'Bennys Original Motor Works', accountNumber: '920-11223344', isCompany: true, maskedNumber: '•••• •••• •••• 8823', status: 'active', isLocked: false, hasPin: true },
];

export const MOCK_PERSONAL_TRANSACTIONS: TbTransaction[] = [
	{ id: 5091, fromAccountId: null, toAccountId: 91, type: 'deposit', amount: 3200, balanceAfter: 18420, actorIdentifier: 'char1:8f2a1c9d0b3e', note: 'Cash deposit', metadata: null, createdAt: '2026-09-27 19:44:12' },
	{ id: 5088, fromAccountId: 91, toAccountId: null, type: 'loan_repayment', amount: 1356, balanceAfter: 15220, actorIdentifier: null, note: 'Automatic loan #7 installment', metadata: null, createdAt: '2026-09-24 08:00:04' },
	{ id: 5080, fromAccountId: null, toAccountId: 97, type: 'interest', amount: 208, balanceAfter: 41900, actorIdentifier: null, note: '1.500% interest', metadata: null, createdAt: '2026-09-23 04:00:00' },
	{ id: 5071, fromAccountId: 91, toAccountId: 94, type: 'transfer', amount: 900, balanceAfter: 6250, actorIdentifier: 'char1:8f2a1c9d0b3e', note: 'Transfer', metadata: null, createdAt: '2026-09-20 14:12:47' },
	{ id: 5060, fromAccountId: 91, toAccountId: null, type: 'standing_order', amount: 1500, balanceAfter: 16576, actorIdentifier: 'char1:8f2a1c9d0b3e', note: 'Rent', metadata: null, createdAt: '2026-09-18 12:00:01' },
	{ id: 5052, fromAccountId: null, toAccountId: 91, type: 'invoice_payment', amount: 2500, balanceAfter: 18076, actorIdentifier: 'char1:2b9e6f1a7c88', note: 'Invoice #201', metadata: null, createdAt: '2026-09-15 09:30:22' },
];

export const MOCK_BUSINESS_TRANSACTIONS: TbTransaction[] = [
	{ id: 1042, fromAccountId: null, toAccountId: 4, type: 'deposit', amount: 9980, balanceAfter: 284730, actorIdentifier: 'char1:8f2a1c9d0b3e', note: 'Register drop', metadata: null, createdAt: '2026-09-13 21:47:02' },
	{ id: 1041, fromAccountId: 4, toAccountId: null, type: 'withdraw', amount: 4300, balanceAfter: 274750, actorIdentifier: 'char1:8f2a1c9d0b3e', note: 'Parts restock', metadata: null, createdAt: '2026-09-13 18:12:55' },
	{ id: 1039, fromAccountId: null, toAccountId: 4, type: 'admin_adjustment', amount: 50000, balanceAfter: 279050, actorIdentifier: 'char1:11f0a7b2c4d9', note: 'Balance set to 279050 by admin', metadata: null, createdAt: '2026-09-08 12:03:17' },
];

export const MOCK_LOAN_HISTORY = [
	{ id: 5, principal: 8000, interestRate: 8.5, totalOwed: 8680, status: 'paid_off' as const, createdAt: '2026-05-02 14:10:00', closedAt: '2026-07-11 09:25:00' },
	{ id: 3, principal: 2500, interestRate: 8.5, totalOwed: 2713, status: 'paid_off' as const, createdAt: '2026-02-18 19:44:00', closedAt: '2026-04-02 16:03:00' },
	{ id: 2, principal: 15000, interestRate: 8.5, totalOwed: 16275, status: 'defaulted' as const, createdAt: '2025-11-30 12:00:00', closedAt: '2026-01-19 08:00:00' },
];

export const MOCK_PERSONAL: TbPersonalOverview = {
	allowed: true,
	accounts: MOCK_ACCOUNTS,
	totalBalance: 66570,
	week: [
		{ day: '2026-09-22', income: 1200, expenses: 400 },
		{ day: '2026-09-23', income: 208, expenses: 0 },
		{ day: '2026-09-24', income: 0, expenses: 1356 },
		{ day: '2026-09-25', income: 3400, expenses: 250 },
		{ day: '2026-09-26', income: 0, expenses: 780 },
		{ day: '2026-09-27', income: 3200, expenses: 0 },
		{ day: '2026-09-28', income: 0, expenses: 120 },
	],
	latestTransactions: MOCK_PERSONAL_TRANSACTIONS,
	openInvoices: [
		{ id: 214, amount: 2500, reason: 'Vehicle repair, front bumper', status: 'pending', dueAt: '2026-10-03 00:00:00', createdAt: '2026-09-26 15:02:11', counterpartyName: 'Bennys Original Motor Works', counterpartyNumber: '920-11223344', direction: 'incoming' },
	],
	loan: { id: 7, accountId: 91, principal: 15000, interestRate: 8.5, totalOwed: 16275, remainingBalance: 9825, installmentAmount: 1356, installmentIntervalSeconds: 604800, nextPaymentDue: '2026-10-01 08:00:00', missedPayments: 0, autoPay: true, status: 'active' },
	loanHistory: MOCK_LOAN_HISTORY,
	cards: MOCK_CARDS,
	standingOrders: [
		{ id: 3, fromAccountId: 91, toAccountNumber: '920-55019921', toName: 'Alta Street Apartments', amount: 1500, intervalSeconds: 604800, nextRunAt: '2026-10-02 12:00:00', note: 'Rent', active: true, failedRuns: 0 },
	],
	limits: { maxAccounts: 3, newAccountPrice: 1000, maxSavings: 2, savingsPrice: 1000, savingsRate: 1.5, savingsLockSeconds: 604800, savingsIntervalSeconds: 86400, feeToBalance: 0.5, maxLoan: 100000, minLoan: 1000, loanPresets: [5000, 10000, 25000, 50000, 100000], minOrderInterval: 3600 },
};

export const MOCK_BUSINESS: TbBusinessView = {
	allowed: true,
	account: MOCK_BUSINESS_ACCOUNT,
	role: 'owner',
	capabilities: { view: true, deposit: true, withdraw: true, manageStaff: true, invoice: true, delete: true },
	days: [
		{ day: '2026-08-30', deposits: 18420, withdrawals: 6200, adminAdjustments: 0 },
		{ day: '2026-08-31', deposits: 9130, withdrawals: 4100, adminAdjustments: 0 },
		{ day: '2026-09-01', deposits: 24980, withdrawals: 11500, adminAdjustments: 0 },
		{ day: '2026-09-02', deposits: 6250, withdrawals: 2000, adminAdjustments: 0 },
		{ day: '2026-09-03', deposits: 15670, withdrawals: 8900, adminAdjustments: 0 },
		{ day: '2026-09-04', deposits: 21040, withdrawals: 3400, adminAdjustments: 0 },
		{ day: '2026-09-05', deposits: 11890, withdrawals: 15200, adminAdjustments: 0 },
		{ day: '2026-09-06', deposits: 8760, withdrawals: 2100, adminAdjustments: 0 },
		{ day: '2026-09-07', deposits: 19340, withdrawals: 7800, adminAdjustments: 0 },
		{ day: '2026-09-08', deposits: 13520, withdrawals: 5600, adminAdjustments: 50000 },
		{ day: '2026-09-09', deposits: 22110, withdrawals: 9300, adminAdjustments: 0 },
		{ day: '2026-09-10', deposits: 7480, withdrawals: 3900, adminAdjustments: 0 },
		{ day: '2026-09-11', deposits: 16230, withdrawals: 12100, adminAdjustments: 0 },
		{ day: '2026-09-12', deposits: 25670, withdrawals: 6700, adminAdjustments: 0 },
		{ day: '2026-09-13', deposits: 9980, withdrawals: 4300, adminAdjustments: 0 },
	],
	latestTransactions: MOCK_BUSINESS_TRANSACTIONS,
	openInvoices: {
		incoming: [],
		outgoing: [
			{ id: 214, amount: 2500, reason: 'Vehicle repair, front bumper', status: 'pending', dueAt: '2026-10-03 00:00:00', createdAt: '2026-09-26 15:02:11', counterpartyName: 'Main account', counterpartyNumber: '920-48271039', direction: 'outgoing' },
		],
	},
	standingOrders: [
		{ id: 9, fromAccountId: 4, toAccountNumber: '920-62004471', toName: 'Main account', amount: 2200, intervalSeconds: 604800, nextRunAt: '2026-09-30 09:00:00', note: 'Salary, L. Ortega', active: true, failedRuns: 0 },
	],
	card: MOCK_CARDS[2],
	canHoldCard: true,
};

export const MOCK_GRADE_ROLES = {
	allowed: true,
	jobName: 'mechanic',
	jobLabel: 'Mechaniker',
	highestIsOwner: true,
	grades: [
		{ grade: 0, label: 'Aushilfe', role: 'contributor' as const, isHighest: false },
		{ grade: 1, label: 'Mechaniker', role: 'contributor' as const, isHighest: false },
		{ grade: 2, label: 'Werkstattleitung', role: 'admin' as const, isHighest: false },
		{ grade: 3, label: 'Inhaber', role: 'owner' as const, isHighest: true },
	],
	capabilities: {
		contributor: { view: true, deposit: true, withdraw: false, manageStaff: false, invoice: false, delete: false },
		admin: { view: true, deposit: true, withdraw: true, manageStaff: true, invoice: true, delete: false },
		owner: { view: true, deposit: true, withdraw: true, manageStaff: true, invoice: true, delete: true },
	},
};

export const MOCK_STAFF: TbStaffMember[] = [
	{ identifier: 'char1:2b9e6f1a7c88', name: 'Marlene Vogt', serverId: 14, role: 'contributor', cardDailyLimit: null },
	{ identifier: 'char1:11f0a7b2c4d9', name: 'Rasim Özdemir', serverId: null, role: 'admin', cardDailyLimit: 15000 },
];

export const MOCK_ATM_SESSION: TbAtmSession = {
	cardId: 12,
	account: MOCK_ACCOUNTS[0],
	isCompany: false,
	dailyLimit: 250000,
	withdrawnToday: 3200,
	quickWithdraw: [500, 1000, 1500, 3000, 5000, 7500],
};

export const MOCK_TAX: TbTaxOverview = {
	enabled: true,
	mode: 'bracket',
	flatRate: 5,
	brackets: [
		{ min: 0, max: 5000, rate: 2 },
		{ min: 5000, max: 25000, rate: 5 },
		{ min: 25000, max: null, rate: 8 },
	],
	minTaxableAmount: 100,
	appliesOn: ['deposit'],
	periodic: null,
	destinationType: 'society',
	destinationName: 'Treasury',
	totalPaid: 1874,
	periodDays: 30,
	paidInPeriod: 236,
	records: [
		{ id: 311, accountId: 91, accountName: 'Main account', taxableAmount: 3200, taxAmount: 64, rate: 2, kind: 'deposit', createdAt: '2026-09-27 19:44:12' },
		{ id: 302, accountId: 91, accountName: 'Main account', taxableAmount: 8600, taxAmount: 172, rate: 5, kind: 'deposit', createdAt: '2026-09-12 11:02:40' },
		{ id: 288, accountId: 94, accountName: 'Car fund', taxableAmount: 1500, taxAmount: 30, rate: 2, kind: 'deposit', createdAt: '2026-08-30 16:20:03' },
		{ id: 271, accountId: 91, accountName: 'Main account', taxableAmount: 26000, taxAmount: 2080, rate: 8, kind: 'deposit', createdAt: '2026-08-14 09:15:55' },
	],
};

export const MOCK_ATM_PAYLOAD: AtmOpenPayload = {
	action: 'open',
	mode: 'atm',
	colors: COLORS,
	currencySymbol: '$',
	defaultLanguage: 'en',
	translations: {},
	features: FEATURES,
	atm: { cardsEnabled: true, cards: MOCK_CARDS, accounts: [] },
};

export const MOCK_BILLING_PAYLOAD: BillingOpenPayload = {
	action: 'open',
	mode: 'billing',
	colors: COLORS,
	currencySymbol: '$',
	defaultLanguage: 'en',
	translations: {},
	features: FEATURES,
	accounts: [MOCK_PERSONAL.accounts[0], { ...MOCK_BUSINESS.account!, jobLabel: 'Mechaniker' }],
	billing: { maxSharePercent: 50, nearbyRadius: 5 },
};

export const MOCK_TERMINAL_PAYLOAD: TerminalOpenPayload = {
	action: 'open',
	mode: 'terminal',
	colors: COLORS,
	currencySymbol: '$',
	defaultLanguage: 'en',
	translations: {},
	features: FEATURES,
	personal: MOCK_PERSONAL,
	businesses: [
		{ accountId: 4, name: 'Bennys Original Motor Works', number: '920-11223344', jobName: 'mechanic', jobLabel: 'Mechaniker', role: 'owner', capabilities: MOCK_BUSINESS.capabilities! },
		{ accountId: 9, name: 'Downtown Cab Co.', number: '920-90817364', jobName: null, jobLabel: null, role: 'contributor', capabilities: { view: true, deposit: true, withdraw: false, manageStaff: false, invoice: false, delete: false } },
	],
	business: MOCK_BUSINESS,
};

/** Browser preview only: the real UI gets these from the game. Loaded lazily so they stay out of the bundle's main chunk. */
export async function loadPreviewTranslations(): Promise<Translations> {
	const files = import.meta.glob<Record<string, string>>('../../../locales/ui/*.json', { import: 'default' });
	const result: Translations = {};

	for (const [path, load] of Object.entries(files)) {
		const code = path.split('/').pop()?.replace('.json', '');

		if (code) {
			result[code] = await load();
		}
	}

	return result;
}
