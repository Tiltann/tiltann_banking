import { useState } from 'react';
import type { ActionResult, TbLoan, TbLoanHistoryEntry } from '../types';
import { fetchNui } from '../api/nui';
import { describeError } from '../errorMessages';
import { useTranslation } from '../i18n/context';
import { formatDate, formatMoney, formatTimestamp } from '../format';
import { BADGE, BTN_GHOST, BTN_PRIMARY, FIELD_LABEL, FORM_ERROR, INPUT, NOTE, PANEL, PANEL_TITLE } from '../ui-classes';

interface LoanPanelProps {
	loan: TbLoan | null;
	history: TbLoanHistoryEntry[];
	minLoan: number;
	maxLoan: number;
	/** Config.Loans.Presets, already filtered server-side to what is actually borrowable. */
	presets: number[];
	currencySymbol: string;
	onChange: () => void;
}

const STATUS_TONE: Record<TbLoanHistoryEntry['status'], 'success' | 'danger' | 'neutral'> = {
	paid_off: 'success',
	defaulted: 'danger',
	cancelled: 'neutral',
};

/** Loan status, request/repay, and what was borrowed before (server/loans/loans.lua). */
export function LoanPanel({ loan, history, minLoan, maxLoan, presets, currencySymbol, onChange }: LoanPanelProps) {
	const { t, lang } = useTranslation();
	const [amount, setAmount] = useState('');
	const [error, setError] = useState<string | undefined>(undefined);
	const [busy, setBusy] = useState(false);

	const money = (value: number) => formatMoney(value, currencySymbol);

	async function submit(requested?: number) {
		const parsed = Math.floor(requested ?? Number(amount));

		if (!parsed || parsed <= 0) {
			return;
		}

		setBusy(true);
		setError(undefined);

		const result = await fetchNui<ActionResult>(loan ? 'tiltann_banking:ui:loans:repay' : 'tiltann_banking:ui:loans:request', { amount: parsed });

		setBusy(false);

		if (!result.ok) {
			setError(describeError(result.errorKey, t));
			return;
		}

		setAmount('');
		onChange();
	}

	return (
		<>
			<section className={PANEL}>
				{loan ? (
					<div className="flex flex-col gap-1.5 text-[13px]">
						<div className="flex justify-between"><span>{t('loan.remaining')}</span><span className="tabular-nums">{money(loan.remainingBalance)}</span></div>
						<div className="flex justify-between"><span>{t('loan.nextInstallment')}</span><span className="tabular-nums">{money(loan.installmentAmount)}</span></div>
						<div className="flex justify-between"><span>{t('loan.nextDue')}</span><span className="tabular-nums">{formatTimestamp(loan.nextPaymentDue, lang)}</span></div>
						{loan.missedPayments > 0 && <p className={FORM_ERROR}>{loan.missedPayments} {t('loan.missed')}</p>}
					</div>
				) : (
					<p className={NOTE}>{t('loan.none')} {t('loan.range', { min: money(minLoan), max: money(maxLoan) })}</p>
				)}

				{error && <p className={FORM_ERROR}>{error}</p>}

				{/* Presets are for borrowing only: a repayment is whatever the
				    player can spare right now, not a menu of round numbers. */}
				{!loan && presets.length > 0 && (
					<div className="flex flex-col gap-1.5">
						<span className={PANEL_TITLE}>{t('loan.presets')}</span>
						<div className="flex flex-wrap gap-2">
							{presets.map((preset) => (
								<button key={preset} type="button" className={BTN_GHOST} onClick={() => submit(preset)} disabled={busy}>
									{money(preset)}
								</button>
							))}
						</div>
					</div>
				)}

				<div className="flex flex-wrap gap-2 items-end">
					<label className={`${FIELD_LABEL} max-w-[220px]`}>
						{t('loan.amount')}
						<input
							className={INPUT}
							type="number"
							min={loan ? 1 : minLoan}
							max={loan ? loan.remainingBalance : maxLoan}
							placeholder={t('common.amount')}
							value={amount}
							onChange={(e) => setAmount(e.target.value)}
							onKeyDown={(e) => e.key === 'Enter' && submit()}
							disabled={busy}
						/>
					</label>
					<button type="button" className={BTN_PRIMARY} onClick={() => submit()} disabled={busy || amount === ''}>
						{loan ? t('loan.repay') : t('loan.request')}
					</button>
				</div>
			</section>

			<section className={PANEL}>
				<h2 className={PANEL_TITLE}>{t('loan.history')}</h2>

				{history.length === 0 ? (
					<p className={NOTE}>{t('loan.historyNone')}</p>
				) : (
					<div className="flex flex-col">
						{history.map((entry) => (
							<div key={entry.id} className="grid [grid-template-columns:1fr_auto] gap-x-4 gap-y-0.5 py-2.5 border-b border-[var(--tb-secondary)]/60 last:border-b-0">
								<span className="text-[13px]">
									{t('loan.borrowed')} {money(entry.principal)}
									<span className="text-[var(--tb-text-muted)]"> · {entry.interestRate}%</span>
								</span>
								<span className="text-[13px] tabular-nums text-right">{money(entry.totalOwed)}</span>
								<span className="text-[11px] text-[var(--tb-text-muted)] tabular-nums">
									{formatDate(entry.createdAt, lang)}
									{entry.closedAt ? ` · ${t('loan.repaidOn', { date: formatDate(entry.closedAt, lang) })}` : ''}
								</span>
								<span className={`${BADGE[STATUS_TONE[entry.status]]} justify-self-end`}>{t(`loan.status.${entry.status}`)}</span>
							</div>
						))}
					</div>
				)}
			</section>
		</>
	);
}
