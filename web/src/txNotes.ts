import type { TranslateFn } from './i18n/context';

/**
 * Transaction notes are written by the Lua side in English and stored as
 * free text, so the statement ("Umsätze") showed them untranslated no matter
 * which language the viewer picked. Rewriting history to store keys instead
 * would orphan every row already in the database, so the known notes are
 * matched here and translated on the way out; anything unrecognised, an
 * admin's own note, a note from a third-party script using the exports,
 * is shown exactly as written.
 */

/** Fixed notes: exact text -> i18n key. */
const EXACT: Record<string, string> = {
	'Cash deposit': 'note.cashDeposit',
	'Cash withdrawal': 'note.cashWithdrawal',
	'Transfer': 'note.transfer',
	'Opening balance': 'note.openingBalance',
	'New account fee': 'note.accountFee',
	'New account fee refund': 'note.accountFeeRefund',
	'Card replacement fee': 'note.cardFee',
	'Periodic balance tax': 'note.balanceTax',
	'External credit': 'note.externalCredit',
	'External debit': 'note.externalDebit',
	'External transfer': 'note.externalTransfer',
	'ATM transfer': 'note.atmTransfer',
	'Withdrawal reverted': 'note.withdrawalReverted',
	'Transfer tax': 'note.transferTax',
	'Balance changed outside the bank': 'note.outsideChange',
	'Company balance changed outside the bank': 'note.outsideChangeCompany',
};

/** Notes carrying a value: pattern -> key + the capture names it fills. */
const PATTERNS: { test: RegExp; key: string; vars: string[] }[] = [
	{ test: /^([\d.]+)% interest$/, key: 'note.interest', vars: ['rate'] },
	{ test: /^(\w+) tax from account #(\d+)$/, key: 'note.taxFrom', vars: ['kind', 'account'] },
	{ test: /^Deposit \((.+)\)$/, key: 'note.depositBy', vars: ['who'] },
	{ test: /^Withdrawal \((.+)\)$/, key: 'note.withdrawalBy', vars: ['who'] },
	{ test: /^Loan #(\d+) disbursed$/, key: 'note.loanDisbursed', vars: ['loan'] },
	{ test: /^Loan #(\d+) repayment$/, key: 'note.loanRepayment', vars: ['loan'] },
	{ test: /^Closed account (.+)$/, key: 'note.closedAccount', vars: ['number'] },
	{ test: /^Balance set to (\d+) by admin$/, key: 'note.adminSetBalance', vars: ['amount'] },
	{ test: /^Balance reset to (-?\d+) outside the bank$/, key: 'note.balanceReset', vars: ['amount'] },
	{ test: /^Automatic loan #(\d+) installment$/, key: 'note.loanInstallment', vars: ['loan'] },
	{ test: /^Invoice #(\d+)$/, key: 'note.invoice', vars: ['invoice'] },
];

/**
 * @param note Raw note from the database, may be null.
 * @param t    The active translation function.
 * @returns The translated note, or the raw text when nothing matches.
 */
export function translateNote(note: string | null | undefined, t: TranslateFn): string | null {
	if (!note) {
		return null;
	}

	const exact = EXACT[note];

	if (exact) {
		return t(exact);
	}

	for (const { test, key, vars } of PATTERNS) {
		const match = note.match(test);

		if (match) {
			const values: Record<string, string> = {};
			vars.forEach((name, index) => {
				values[name] = match[index + 1];
			});
			if (key === 'note.balanceReset') {
				values.amount = Number(values.amount).toLocaleString('en-US');
			}
			if (key === 'note.taxFrom') {
				// the kind arrives as the English word the server used, show it in the viewer's language
				const kindKey = `tax.kind.${values.kind}`;
				const kindText = t(kindKey);
				values.kind = kindText === kindKey ? values.kind : kindText;
			}

			return t(key, values);
		}
	}

	return note;
}
