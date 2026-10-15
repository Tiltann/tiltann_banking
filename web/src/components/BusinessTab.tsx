import { useEffect, useRef, useState } from 'react';
import type { ActionResult, TbBusinessSummary, TbBusinessView, TbFeatureToggles, TbTransactionFilters, TbUiColors } from '../types';
import { fetchNui } from '../api/nui';
import { describeError } from '../errorMessages';
import { useTranslation } from '../i18n/context';
import { formatMoney } from '../format';
import { CardIcon, ChevronDownIcon, DashboardIcon, InvoiceIcon, ListIcon, RepeatIcon, TransferIcon, UsersIcon } from '../icons';
import { BADGE, BTN_GHOST, FORM_ERROR, INPUT, PAGE_TITLE, PANEL, PANEL_TITLE } from '../ui-classes';
import { CardItem, RequestCardButton } from './CardsPanel';
import { ClearHistoryButton } from './ClearHistoryButton';
import { InvoicePanel } from './InvoicePanel';
import { MoneyActions } from './MoneyActions';
import { PayoutChart } from './PayoutChart';
import { StaffPanel } from './StaffPanel';
import { StandingOrdersPanel } from './StandingOrdersPanel';
import { StatCard } from './StatCard';
import { RailLayout, SubNav } from './SubNav';
import { BlurFade } from './ui/BlurFade';
import { NumberTicker } from './ui/NumberTicker';
import type { SubNavItem } from './SubNav';
import { TransactionFilters } from './TransactionFilters';
import { TransactionTable } from './TransactionTable';
import { TxList } from './TxList';

type Section = 'dashboard' | 'transactions' | 'actions' | 'invoices' | 'orders' | 'cards' | 'staff';

interface BusinessTabProps {
	businesses: TbBusinessSummary[];
	initial: TbBusinessView | null;
	features: TbFeatureToggles;
	currencySymbol: string;
	colors: TbUiColors;
}

/** The terminal's Business tab: one business at a time (switcher when the player has several), split into focused pages by what their role allows. */
export function BusinessTab({ businesses, initial, features, currencySymbol, colors }: BusinessTabProps) {
	const { t } = useTranslation();
	const [accountId, setAccountId] = useState(businesses[0]?.accountId ?? 0);
	const [view, setView] = useState<TbBusinessView | null>(initial);
	const [section, setSection] = useState<Section>('dashboard');
	const [switching, setSwitching] = useState(false);
	const [filters, setFilters] = useState<TbTransactionFilters | undefined>(undefined);
	const [txVersion, setTxVersion] = useState(0);

	const currentId = useRef(accountId);
	currentId.current = accountId;

	useEffect(() => {
		const onRefresh = () => {
			load(currentId.current);
		};

		window.addEventListener('tb:refresh', onRefresh);
		return () => window.removeEventListener('tb:refresh', onRefresh);
	}, []);

	async function load(id: number) {
		setView(await fetchNui<TbBusinessView>('tiltann_banking:ui:business:get', { accountId: id }));
	}

	async function switchTo(id: number) {
		if (id === accountId) return;
		setSwitching(true);
		setAccountId(id);
		setSection('dashboard');
		await load(id);
		setSwitching(false);
	}

	if (!view || !view.allowed || !view.account || !view.capabilities || !view.role) {
		return <p className="text-[var(--tb-text-muted)] text-[13px] text-center py-6">{t('common.loading')}</p>;
	}

	const account = view.account;
	const caps = view.capabilities;
	const reload = () => load(accountId);

	const items: SubNavItem<Section>[] = [
		{ key: 'dashboard', label: t('nav.dashboard'), icon: <DashboardIcon width={15} height={15} /> },
		{ key: 'transactions', label: t('nav.transactions'), icon: <ListIcon width={15} height={15} /> },
	];

	if (caps.deposit || caps.withdraw) items.push({ key: 'actions', label: t('nav.actions'), icon: <TransferIcon width={15} height={15} /> });
	if (features.billingEnabled && (caps.invoice || caps.withdraw)) items.push({ key: 'invoices', label: t('nav.invoices'), icon: <InvoiceIcon width={15} height={15} /> });
	if (features.standingOrdersEnabled && caps.withdraw) items.push({ key: 'orders', label: t('nav.orders'), icon: <RepeatIcon width={15} height={15} /> });
	if (view.canHoldCard) items.push({ key: 'cards', label: t('nav.cards'), icon: <CardIcon width={15} height={15} /> });
	if (caps.manageStaff) items.push({ key: 'staff', label: t('nav.staff'), icon: <UsersIcon width={15} height={15} /> });

	const days = view.days ?? [];
	const net = days.reduce((sum, day) => sum + day.deposits - day.withdrawals, 0);
	const title = items.find((item) => item.key === section)?.label ?? '';

	const nav = (
		<div className="flex flex-col gap-4">
			<div className="flex flex-col gap-1.5 px-3">
				{businesses.length > 1 ? (
					<div className="relative -mx-3">
						<select
							className="w-full appearance-none bg-[var(--tb-surface)] text-[var(--tb-text-primary)] rounded-lg pl-3 pr-7 py-2 text-[13px] font-semibold cursor-pointer focus:outline-none"
							value={accountId}
							disabled={switching}
							onChange={(event) => switchTo(Number(event.target.value))}
						>
							{businesses.map((business) => (
								<option key={business.accountId} value={business.accountId}>{business.name}</option>
							))}
						</select>
						<ChevronDownIcon width={14} height={14} className="pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 text-[var(--tb-text-muted)]" />
					</div>
				) : (
					<span className="text-[14px] font-semibold truncate">{account.name}</span>
				)}
				<span className="flex items-center gap-2 text-[11px] text-[var(--tb-text-muted)]">
					<span className={BADGE.accent}>{t(`business.role.${view.role}`)}</span>
					{account.jobName && <span className="truncate">{account.jobLabel || account.jobName} · {t('business.viaJob')}</span>}
				</span>
			</div>
			<SubNav id="business" items={items} active={section} onChange={setSection} />
		</div>
	);

	return (
		<RailLayout nav={nav} pageKey={`${accountId}:${section}`}>
			{section !== 'dashboard' && <h1 className={PAGE_TITLE}>{title}</h1>}

			{section === 'dashboard' && (
				<>
					<BlurFade>
						<div className="flex items-end justify-between gap-4 flex-wrap">
							<div className="flex flex-col gap-1">
								<span className="text-[11px] uppercase tracking-[0.08em] text-[var(--tb-text-muted)]">{t('stat.balance')}</span>
								<NumberTicker value={account.balance} format={(value) => formatMoney(value, currencySymbol)} className="text-[40px] leading-none font-semibold tabular-nums tracking-tight" />
								<span className="text-xs text-[var(--tb-text-muted)] tabular-nums mt-1">{account.number}</span>
							</div>
							<StatCard label={t('stat.net30')} value={net} format={(value) => `${value >= 0 ? '+' : '-'}${formatMoney(Math.abs(value), currencySymbol)}`} tone={net >= 0 ? 'success' : 'danger'} />
						</div>
					</BlurFade>

					<BlurFade delay={0.08}>
						<section className={PANEL}>
							<h2 className={PANEL_TITLE}>{t('chart.title')}</h2>
							<PayoutChart days={days} colors={colors} currencySymbol={currencySymbol} />
						</section>
					</BlurFade>

					<BlurFade delay={0.14}>
						<section className={PANEL}>
							<h2 className={PANEL_TITLE}>{t('tx.title')}</h2>
							<TxList transactions={view.latestTransactions ?? []} ownedIds={new Set([account.id])} currencySymbol={currencySymbol} />
						</section>
					</BlurFade>

					{view.role === 'owner' && <RenameBusiness accountId={accountId} currentName={account.name} onChange={reload} />}
				</>
			)}

			{section === 'transactions' && (
				<section className={PANEL}>
					<TransactionFilters onChange={setFilters} />
					{features.clearHistoryEnabled && caps.delete && (
						<ClearHistoryButton
							key={accountId}
							endpoint="tiltann_banking:ui:business:clearHistory"
							accountId={accountId}
							onCleared={() => {
								setTxVersion((v) => v + 1);
								reload();
							}}
						/>
					)}
					<TransactionTable key={`${accountId}:${txVersion}`} accountId={accountId} currencySymbol={currencySymbol} filters={filters} />
				</section>
			)}

			{section === 'actions' && (
				<section className={PANEL}>
					<MoneyActions
						canDeposit={caps.deposit}
						canWithdraw={caps.withdraw}
						onDeposit={(amount) => fetchNui('tiltann_banking:ui:business:deposit', { accountId, amount })}
						onWithdraw={(amount) => fetchNui('tiltann_banking:ui:business:withdraw', { accountId, amount })}
						onSuccess={reload}
					/>
				</section>
			)}

			{section === 'invoices' && <InvoicePanel key={accountId} accounts={[account]} currencySymbol={currencySymbol} canSend={caps.invoice} canPay={caps.withdraw} onMoneyMoved={reload} />}

			{section === 'orders' && (
				<StandingOrdersPanel key={accountId} accounts={[account]} currencySymbol={currencySymbol} minIntervalSeconds={3600} canCreate={caps.withdraw} />
			)}

			{section === 'cards' && (
				<section className={PANEL}>
					<h2 className={PANEL_TITLE}>{t('card.company')}</h2>
					{view.card ? <CardItem card={view.card} onChange={reload} /> : <RequestCardButton accountId={accountId} label={account.name} onChange={reload} />}
				</section>
			)}

			{section === 'staff' && <StaffPanel key={accountId} accountId={accountId} ownRole={view.role} currencySymbol={currencySymbol} />}
		</RailLayout>
	);
}

function RenameBusiness({ accountId, currentName, onChange }: { accountId: number; currentName: string; onChange: () => void }) {
	const { t } = useTranslation();
	const [name, setName] = useState(currentName);
	const [error, setError] = useState<string | undefined>(undefined);
	const [busy, setBusy] = useState(false);

	async function rename() {
		setBusy(true);
		setError(undefined);

		const result = await fetchNui<ActionResult>('tiltann_banking:ui:business:rename', { accountId, name: name.trim() });

		setBusy(false);

		if (!result.ok) {
			setError(describeError(result.errorKey, t));
			return;
		}

		onChange();
	}

	return (
		<div className="flex flex-wrap items-center gap-2">
			<input className={`${INPUT} max-w-[260px]`} type="text" maxLength={25} value={name} onChange={(e) => setName(e.target.value)} disabled={busy} />
			<button type="button" className={BTN_GHOST} onClick={rename} disabled={busy || name.trim() === '' || name === currentName}>
				{t('business.rename')}
			</button>
			{error && <span className={FORM_ERROR}>{error}</span>}
		</div>
	);
}
