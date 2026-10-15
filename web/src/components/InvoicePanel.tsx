import { useEffect, useState } from 'react';
import type { ActionResult, TbAccount, TbInvoiceView } from '../types';
import { fetchNui } from '../api/nui';
import { describeError } from '../errorMessages';
import { useTranslation } from '../i18n/context';
import { formatMoney, formatTimestamp } from '../format';
import { CheckIcon, CloseIcon, SendIcon } from '../icons';
import { BADGE, BTN_GHOST, BTN_PRIMARY, FORM_ERROR, INPUT, NOTE, PANEL, PANEL_TITLE, SELECT } from '../ui-classes';

interface InvoicePanelProps {
	/** Accounts the viewer can bill from / pay with. One entry for a business. */
	accounts: TbAccount[];
	currencySymbol: string;
	canSend: boolean;
	canPay: boolean;
	/** Per-account overrides for business accounts in the list (the viewer's role decides there). */
	caps?: Record<number, { canSend: boolean; canPay: boolean }>;
	onMoneyMoved: () => void;
}

interface OpenInvoices {
	incoming: TbInvoiceView[];
	outgoing: TbInvoiceView[];
	past?: TbInvoiceView[];
}

/** Business accounts show their business and job so they are not mistaken for a personal account. */
function accountLabel(account: TbAccount): string {
	const job = account.type === 'society' && account.jobLabel && account.jobLabel !== account.name ? ` (${account.jobLabel})` : '';
	return `${account.name}${job} · ${account.number}`;
}

/** "Name · account number · person", so it is clear where an invoice comes from. */
function counterparty(invoice: TbInvoiceView): string {
	return [invoice.counterpartyName, invoice.counterpartyNumber, invoice.counterpartyPerson].filter(Boolean).join(' · ');
}

/** Open invoices for the selected account (to pay / sent) plus a "new invoice" form. */
export function InvoicePanel({ accounts, currencySymbol, canSend: canSendAll, canPay: canPayAll, caps, onMoneyMoved }: InvoicePanelProps) {
	const { t, lang } = useTranslation();
	const [accountId, setAccountId] = useState(accounts[0]?.id ?? 0);
	const [open, setOpen] = useState<OpenInvoices>({ incoming: [], outgoing: [] });
	const [recipient, setRecipient] = useState('');
	const [amount, setAmount] = useState('');
	const [reason, setReason] = useState('');
	const [error, setError] = useState<string | undefined>(undefined);
	const [busy, setBusy] = useState(false);
	const [showPast, setShowPast] = useState(false);
	const canSend = caps?.[accountId]?.canSend ?? canSendAll;
	const canPay = caps?.[accountId]?.canPay ?? canPayAll;

	async function load(id: number) {
		setOpen(await fetchNui<OpenInvoices>('tiltann_banking:ui:billing:getOpen', { accountId: id }));
	}

	useEffect(() => {
		if (accountId) {
			load(accountId);
		}
	}, [accountId]);

	async function run(action: () => Promise<ActionResult>, moved: boolean) {
		setBusy(true);
		setError(undefined);

		const result = await action();

		setBusy(false);

		if (!result.ok) {
			setError(describeError(result.errorKey, t));
			return false;
		}

		await load(accountId);

		if (moved) {
			onMoneyMoved();
		}

		return true;
	}

	async function send() {
		const parsed = Math.floor(Number(amount));

		if (!parsed || parsed <= 0 || recipient.trim() === '') {
			return;
		}

		const ok = await run(
			() => fetchNui('tiltann_banking:ui:billing:send', { fromAccountId: accountId, recipient: recipient.trim(), amount: parsed, reason: reason.trim() }),
			false
		);

		if (ok) {
			setRecipient('');
			setAmount('');
			setReason('');
		}
	}

	return (
		<section className={PANEL}>
			{accounts.length > 1 && (
					<select className={`${SELECT} self-start`} value={accountId} onChange={(e) => setAccountId(Number(e.target.value))}>
						{accounts.map((account) => (
							<option key={account.id} value={account.id}>{accountLabel(account)}</option>
						))}
					</select>
				)}

			{error && <p className={FORM_ERROR}>{error}</p>}

			<h3 className={PANEL_TITLE}>{t('invoice.incoming')}</h3>
			<p className={NOTE}>{t('invoice.autoCharge')}</p>
			{open.incoming.length === 0 ? (
				<p className={NOTE}>{t('invoice.none')}</p>
			) : (
				<div className="flex flex-col">
					{open.incoming.map((invoice) => (
						<div key={invoice.id} className="flex items-center justify-between gap-3 py-2.5 border-b border-[var(--tb-secondary)]/60 last:border-b-0 flex-wrap">
							<div className="flex flex-col gap-0.5">
								<span className="font-semibold tabular-nums">
									<span className="text-[var(--tb-text-muted)] mr-2">#{invoice.id}</span>{formatMoney(invoice.amount, currencySymbol)}
									{invoice.status === 'overdue' && <span className={`${BADGE.danger} ml-2`}>{t('invoice.overdue')}</span>}
								</span>
								<span className="text-xs text-[var(--tb-text-muted)]">
									{t('invoice.from')} {counterparty(invoice)}{invoice.reason ? ` · ${invoice.reason}` : ''}
									{invoice.dueAt ? ` · ${t('invoice.due')} ${formatTimestamp(invoice.dueAt, lang)}` : ''}
								</span>
							</div>
							{canPay && (
								<div className="flex gap-2 shrink-0">
									<button type="button" className={BTN_PRIMARY} onClick={() => run(() => fetchNui('tiltann_banking:ui:billing:pay', { invoiceId: invoice.id }), true)} disabled={busy}>
										<CheckIcon width={14} height={14} /> {t('invoice.pay')}
									</button>
									{invoice.canDecline && (
										<button type="button" className={BTN_GHOST} onClick={() => run(() => fetchNui('tiltann_banking:ui:billing:decline', { invoiceId: invoice.id }), false)} disabled={busy}>
											<CloseIcon width={14} height={14} /> {t('invoice.decline')}
										</button>
									)}
								</div>
							)}
						</div>
					))}
				</div>
			)}

			<h3 className={PANEL_TITLE}>{t('invoice.outgoing')}</h3>
			{open.outgoing.length === 0 ? (
				<p className={NOTE}>{t('invoice.none')}</p>
			) : (
				<div className="flex flex-col">
					{open.outgoing.map((invoice) => (
						<div key={invoice.id} className="flex items-center justify-between gap-3 py-2.5 border-b border-[var(--tb-secondary)]/60 last:border-b-0">
							<span className="text-xs text-[var(--tb-text-muted)]">
								#{invoice.id} · {t('invoice.to')} {counterparty(invoice)}{invoice.reason ? ` · ${invoice.reason}` : ''}
							</span>
							<span className="font-semibold tabular-nums">{formatMoney(invoice.amount, currencySymbol)}</span>
						</div>
					))}
				</div>
			)}

			<div className="flex items-center justify-between">
				<h3 className={PANEL_TITLE}>{t('invoice.history')}</h3>
				<button type="button" className={BTN_GHOST} onClick={() => setShowPast((v) => !v)}>
					{showPast ? t('invoice.hide') : t('invoice.show')}
				</button>
			</div>
			{showPast && ((open.past ?? []).length === 0 ? (
				<p className={NOTE}>{t('invoice.historyEmpty')}</p>
			) : (
				<div className="flex flex-col">
					{(open.past ?? []).map((invoice) => (
						<div key={invoice.id} className="flex items-center justify-between gap-3 py-2.5 border-b border-[var(--tb-secondary)]/60 last:border-b-0 flex-wrap">
							<div className="flex flex-col gap-0.5">
								<span className="font-semibold tabular-nums">
									<span className="text-[var(--tb-text-muted)] mr-2">#{invoice.id}</span>{formatMoney(invoice.amount, currencySymbol)}
									<span className={`${invoice.status === 'paid' ? BADGE.success : BADGE.neutral} ml-2`}>{t(`invoice.status.${invoice.status}`)}</span>
								</span>
								<span className="text-xs text-[var(--tb-text-muted)]">
									{invoice.direction === 'incoming' ? t('invoice.from') : t('invoice.to')} {counterparty(invoice)}{invoice.reason ? ` · ${invoice.reason}` : ''}
									{` · ${formatTimestamp(invoice.resolvedAt ?? invoice.createdAt, lang)}`}
								</span>
							</div>
						</div>
					))}
				</div>
			))}

			{canSend && (
				<>
					<h3 className={PANEL_TITLE}>{t('invoice.newTitle')}</h3>
					<div className="flex flex-wrap gap-2.5 items-stretch">
						<input className={INPUT} type="text" placeholder={t('invoice.recipient')} title={t('recipient.hint')} value={recipient} onChange={(e) => setRecipient(e.target.value)} disabled={busy} />
						<input className={INPUT} type="number" min={1} placeholder={t('common.amount')} value={amount} onChange={(e) => setAmount(e.target.value)} disabled={busy} />
						<input className={INPUT} type="text" placeholder={t('invoice.reason')} value={reason} onChange={(e) => setReason(e.target.value)} disabled={busy} />
						<button type="button" className={BTN_PRIMARY} onClick={send} disabled={busy || recipient.trim() === '' || amount === ''}>
							<SendIcon width={14} height={14} /> {t('invoice.send')}
						</button>
					</div>
					<p className={NOTE}>{t('recipient.hint')}</p>
				</>
			)}
		</section>
	);
}
