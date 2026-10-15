import { useState } from 'react';
import type { ReactNode } from 'react';
import { describeError } from '../errorMessages';
import { useTranslation } from '../i18n/context';
import { DepositIcon, WithdrawIcon } from '../icons';
import { BTN_PRIMARY, FORM_ERROR, INPUT } from '../ui-classes';
import type { ActionResult } from '../types';

interface MoneyActionsProps {
	canDeposit?: boolean;
	canWithdraw?: boolean;
	onDeposit: (amount: number) => Promise<ActionResult>;
	onWithdraw: (amount: number) => Promise<ActionResult>;
	onSuccess: () => void;
}

interface AmountFieldProps {
	label: string;
	icon: ReactNode;
	onSubmit: (amount: number) => Promise<ActionResult>;
	onDone: () => void;
}

function AmountField({ label, icon, onSubmit, onDone }: AmountFieldProps) {
	const { t } = useTranslation();
	const [amount, setAmount] = useState('');
	const [error, setError] = useState<string | undefined>(undefined);
	const [submitting, setSubmitting] = useState(false);

	async function submit() {
		const parsed = Math.floor(Number(amount));

		if (!parsed || parsed <= 0) {
			return;
		}

		setSubmitting(true);
		setError(undefined);

		const result = await onSubmit(parsed);

		setSubmitting(false);

		if (!result.ok) {
			setError(describeError(result.errorKey, t));
			return;
		}

		setAmount('');
		onDone();
	}

	return (
		<div className="flex flex-col gap-1.5">
			<span className="flex items-center gap-1.5 text-[11px] uppercase tracking-[0.08em] text-[var(--tb-text-muted)]">{icon} {label}</span>
			<div className="flex gap-2">
				<input
					className={INPUT}
					type="number"
					min={1}
					placeholder={t('common.amount')}
					value={amount}
					onChange={(event) => setAmount(event.target.value)}
					onKeyDown={(event) => event.key === 'Enter' && submit()}
					disabled={submitting}
				/>
				<button type="button" className={BTN_PRIMARY} onClick={submit} disabled={submitting || amount === ''}>
					{submitting ? '...' : label}
				</button>
			</div>
			{error && <p className={FORM_ERROR}>{error}</p>}
		</div>
	);
}

/** Cash in / cash out for one account, shared by the ATM, the Personal accounts page and the Business actions page. */
export function MoneyActions({ canDeposit = true, canWithdraw = true, onDeposit, onWithdraw, onSuccess }: MoneyActionsProps) {
	const { t } = useTranslation();

	return (
		<div className="grid [grid-template-columns:repeat(auto-fit,minmax(240px,1fr))] items-start gap-4">
			{canDeposit && <AmountField label={t('actions.deposit')} icon={<DepositIcon width={13} height={13} />} onSubmit={onDeposit} onDone={onSuccess} />}
			{canWithdraw && <AmountField label={t('actions.withdraw')} icon={<WithdrawIcon width={13} height={13} />} onSubmit={onWithdraw} onDone={onSuccess} />}
		</div>
	);
}
