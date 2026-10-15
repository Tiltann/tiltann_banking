import { useEffect, useState } from 'react';
import type { ActionResult, TbAccount, TbStandingOrder } from '../types';
import { fetchNui } from '../api/nui';
import { describeError } from '../errorMessages';
import { useTranslation } from '../i18n/context';
import { formatMoney, formatTimestamp } from '../format';
import { TrashIcon } from '../icons';
import { BADGE, BTN_GHOST, BTN_PRIMARY, FORM_ERROR, INPUT, NOTE, PANEL, PANEL_TITLE, SELECT } from '../ui-classes';

interface StandingOrdersPanelProps {
	/** Accounts orders may run from. One entry for a business. */
	accounts: TbAccount[];
	currencySymbol: string;
	minIntervalSeconds: number;
	canCreate: boolean;
}

const INTERVALS: { key: string; seconds: number }[] = [
	{ key: 'orders.interval.day', seconds: 86400 },
	{ key: 'orders.interval.week', seconds: 604800 },
	{ key: 'orders.interval.month', seconds: 2592000 },
];

/** Recurring transfers from the selected account: the list, and a form to add one. */
export function StandingOrdersPanel({ accounts, currencySymbol, minIntervalSeconds, canCreate }: StandingOrdersPanelProps) {
	const { t, lang } = useTranslation();
	const [accountId, setAccountId] = useState(accounts[0]?.id ?? 0);
	const [orders, setOrders] = useState<TbStandingOrder[]>([]);
	const [toNumber, setToNumber] = useState('');
	const [amount, setAmount] = useState('');
	const [interval, setIntervalSeconds] = useState(INTERVALS.find((option) => option.seconds >= minIntervalSeconds)?.seconds ?? 604800);
	const [note, setNote] = useState('');
	const [error, setError] = useState<string | undefined>(undefined);
	const [busy, setBusy] = useState(false);

	async function load(id: number) {
		setOrders(await fetchNui<TbStandingOrder[]>('tiltann_banking:ui:orders:list', { accountId: id }));
	}

	useEffect(() => {
		if (accountId) {
			load(accountId);
		}
	}, [accountId]);

	async function run(action: () => Promise<ActionResult>) {
		setBusy(true);
		setError(undefined);

		const result = await action();

		setBusy(false);

		if (!result.ok) {
			setError(describeError(result.errorKey, t));
			return false;
		}

		await load(accountId);
		return true;
	}

	async function create() {
		const parsed = Math.floor(Number(amount));

		if (!parsed || parsed <= 0 || toNumber.trim() === '') {
			return;
		}

		const ok = await run(() =>
			fetchNui('tiltann_banking:ui:orders:create', { fromAccountId: accountId, toNumber: toNumber.trim(), amount: parsed, intervalSeconds: interval, note: note.trim() })
		);

		if (ok) {
			setToNumber('');
			setAmount('');
			setNote('');
		}
	}

	return (
		<section className={PANEL}>
			{accounts.length > 1 && (
					<select className={`${SELECT} self-start`} value={accountId} onChange={(e) => setAccountId(Number(e.target.value))}>
						{accounts.map((account) => (
							<option key={account.id} value={account.id}>{`${account.name} · ${account.number}`}</option>
						))}
					</select>
				)}

			{error && <p className={FORM_ERROR}>{error}</p>}

			{orders.length === 0 ? (
				<p className={NOTE}>{t('orders.none')}</p>
			) : (
				<div className="flex flex-col">
					{orders.map((order) => (
						<div key={order.id} className="flex items-center justify-between gap-3 py-2.5 border-b border-[var(--tb-secondary)]/60 last:border-b-0 flex-wrap">
							<div className="flex flex-col gap-0.5">
								<span className="font-semibold tabular-nums">
									{formatMoney(order.amount, currencySymbol)}
									<span className="text-xs text-[var(--tb-text-muted)] font-normal ml-2">
										{t('orders.every')} {t(INTERVALS.find((option) => option.seconds === order.intervalSeconds)?.key ?? 'orders.interval.week').toLowerCase()}
									</span>
									{!order.active && <span className={`${BADGE.warning} ml-2`}>{t('orders.inactive')}</span>}
								</span>
								<span className="text-xs text-[var(--tb-text-muted)]">
									{t('invoice.to')} {order.toName ?? order.toAccountNumber}{order.note ? ` · ${order.note}` : ''} · {t('orders.next')} {formatTimestamp(order.nextRunAt, lang)}
									{order.failedRuns > 0 ? ` · ${t('orders.failed', { count: order.failedRuns })}` : ''}
								</span>
							</div>
							{canCreate && (
								<button type="button" className={BTN_GHOST} onClick={() => run(() => fetchNui('tiltann_banking:ui:orders:cancel', { orderId: order.id }))} disabled={busy}>
									<TrashIcon width={14} height={14} /> {t('orders.cancel')}
								</button>
							)}
						</div>
					))}
				</div>
			)}

			{canCreate && (
				<>
					<h3 className={PANEL_TITLE}>{t('orders.new')}</h3>
					<div className="flex flex-wrap gap-2.5 items-stretch">
						<input className={INPUT} type="text" placeholder={t('orders.toNumber')} title={t('recipient.hint')} value={toNumber} onChange={(e) => setToNumber(e.target.value)} disabled={busy} />
						<input className={INPUT} type="number" min={1} placeholder={t('common.amount')} value={amount} onChange={(e) => setAmount(e.target.value)} disabled={busy} />
						<select className={SELECT} value={interval} onChange={(e) => setIntervalSeconds(Number(e.target.value))} disabled={busy}>
							{INTERVALS.filter((option) => option.seconds >= minIntervalSeconds).map((option) => (
								<option key={option.seconds} value={option.seconds}>{t('orders.every')} {t(option.key).toLowerCase()}</option>
							))}
						</select>
						<input className={INPUT} type="text" placeholder={t('common.note')} value={note} onChange={(e) => setNote(e.target.value)} disabled={busy} />
						<button type="button" className={BTN_PRIMARY} onClick={create} disabled={busy || toNumber.trim() === '' || amount === ''}>
							{t('orders.create')}
						</button>
					</div>
					<p className={NOTE}>{t('recipient.hint')}</p>
				</>
			)}
		</section>
	);
}
