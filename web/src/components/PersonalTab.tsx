import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import type { ActionResult, TbAccount, TbBusinessSummary, TbFeatureToggles, TbPersonalOverview, TbTransactionFilters, TbUiColors } from '../types';
import { fetchNui } from '../api/nui';
import { describeError } from '../errorMessages';
import { useTranslation } from '../i18n/context';
import { formatDate, formatMoney } from '../format';
import { durationLabel, intervalLabel } from '../duration';
import { useSavingsLock } from '../hooks/useSavingsLock';
import { CardIcon, DashboardIcon, DepositIcon, InvoiceIcon, ListIcon, LoanIcon, LockIcon, PercentIcon, PlusIcon, RepeatIcon, StarIcon, TransferIcon, TrashIcon, WalletIcon, WithdrawIcon } from '../icons';
import { BADGE, BTN_DANGER, BTN_GHOST, BTN_PRIMARY, FIELD_LABEL, FORM_ERROR, INPUT, NOTE, PAGE_TITLE, PANEL, PANEL_TITLE, SELECT } from '../ui-classes';
import { AccountTile } from './AccountTile';
import { ClearHistoryButton } from './ClearHistoryButton';
import { CardsPanel } from './CardsPanel';
import { InvoicePanel } from './InvoicePanel';
import { LoanPanel } from './LoanPanel';
import { MoneyActions } from './MoneyActions';
import { StandingOrdersPanel } from './StandingOrdersPanel';
import { StatCard } from './StatCard';
import { TaxPanel } from './TaxPanel';
import { RailLayout, SubNav } from './SubNav';
import type { SubNavItem } from './SubNav';
import { TransactionFilters } from './TransactionFilters';
import { TransactionTable } from './TransactionTable';
import { TxList } from './TxList';
import { BlurFade } from './ui/BlurFade';
import { NumberTicker } from './ui/NumberTicker';
import { Tooltip } from './ui/Tooltip';
import { WeekGraph } from './WeekGraph';

type Section = 'dashboard' | 'accounts' | 'transfer' | 'transactions' | 'invoices' | 'loans' | 'cards' | 'orders' | 'tax';

interface PersonalTabProps {
	initial: TbPersonalOverview;
	features: TbFeatureToggles;
	currencySymbol: string;
	colors: TbUiColors;
	businesses?: TbBusinessSummary[];
}

/** The terminal's Personal tab: the pefcl-style dashboard plus one focused page per concern. No card gate here. */
export function PersonalTab({ initial, features, currencySymbol, colors, businesses = [] }: PersonalTabProps) {
	const { t } = useTranslation();
	const [overview, setOverview] = useState(initial);
	const [section, setSection] = useState<Section>('dashboard');
	const [selectedId, setSelectedId] = useState(initial.accounts[0]?.id ?? 0);

	async function reload() {
		setOverview(await fetchNui<TbPersonalOverview>('tiltann_banking:ui:personal:get'));
	}

	useEffect(() => {
		const onRefresh = () => {
			reload();
		};

		window.addEventListener('tb:refresh', onRefresh);
		return () => window.removeEventListener('tb:refresh', onRefresh);
	}, []);

	const items: SubNavItem<Section>[] = [
		{ key: 'dashboard', label: t('nav.dashboard'), icon: <DashboardIcon width={15} height={15} /> },
		{ key: 'accounts', label: t('nav.accounts'), icon: <WalletIcon width={15} height={15} /> },
		{ key: 'transfer', label: t('nav.transfer'), icon: <TransferIcon width={15} height={15} /> },
		{ key: 'transactions', label: t('nav.transactions'), icon: <ListIcon width={15} height={15} /> },
	];

	if (features.billingEnabled) items.push({ key: 'invoices', label: t('nav.invoices'), icon: <InvoiceIcon width={15} height={15} />, badge: overview.openInvoices.length });
	if (features.loansEnabled) items.push({ key: 'loans', label: t('nav.loans'), icon: <LoanIcon width={15} height={15} /> });
	if (features.cardsEnabled) items.push({ key: 'cards', label: t('nav.cards'), icon: <CardIcon width={15} height={15} /> });
	if (features.standingOrdersEnabled) items.push({ key: 'orders', label: t('nav.orders'), icon: <RepeatIcon width={15} height={15} /> });
	if (features.taxEnabled) items.push({ key: 'tax', label: t('nav.tax'), icon: <PercentIcon width={15} height={15} /> });

	const personalAccounts = overview.accounts.filter((account) => account.type === 'personal');

	// Business accounts the viewer may bill from or pay for, shown next to the personal ones in the invoice picker.
	const invoiceBusinesses = businesses.filter((business) => business.capabilities.invoice || business.capabilities.withdraw);
	const invoiceAccounts: TbAccount[] = [
		...personalAccounts,
		...invoiceBusinesses.map((business): TbAccount => ({
			id: business.accountId,
			type: 'society',
			ownerIdentifier: null,
			jobName: business.jobName,
			jobLabel: business.jobLabel,
			number: business.number,
			name: business.name,
			balance: 0,
			isDefault: false,
			isTreasury: false,
			interestRate: null,
			lockedUntil: null,
			createdAt: null,
		})),
	];
	const invoiceCaps = Object.fromEntries(invoiceBusinesses.map((business) => [business.accountId, { canSend: business.capabilities.invoice, canPay: business.capabilities.withdraw }]));
	const selected = overview.accounts.find((account) => account.id === selectedId) ?? overview.accounts[0];
	const title = items.find((item) => item.key === section)?.label ?? '';

	function openAccount(account: TbAccount) {
		setSelectedId(account.id);
		setSection('accounts');
	}

	return (
		<RailLayout nav={<SubNav id="personal" items={items} active={section} onChange={setSection} />} pageKey={section}>
			{section !== 'dashboard' && <h1 className={PAGE_TITLE}>{title}</h1>}

			{section === 'dashboard' && (
				<Dashboard overview={overview} features={features} currencySymbol={currencySymbol} colors={colors} onOpenAccount={openAccount} onGo={setSection} />
			)}

			{section === 'accounts' && selected && (
				<Accounts overview={overview} selected={selected} onSelect={(account) => setSelectedId(account.id)} currencySymbol={currencySymbol} features={features} reload={reload} />
			)}

			{section === 'transfer' && <Transfer accounts={overview.accounts} currencySymbol={currencySymbol} reload={reload} />}

			{section === 'transactions' && <Transactions accounts={overview.accounts} currencySymbol={currencySymbol} features={features} reload={reload} />}

			{section === 'invoices' && <InvoicePanel accounts={invoiceAccounts} caps={invoiceCaps} currencySymbol={currencySymbol} canSend canPay onMoneyMoved={reload} />}

			{section === 'loans' && (
				<LoanPanel
					loan={overview.loan}
					history={overview.loanHistory}
					minLoan={overview.limits.minLoan}
					maxLoan={overview.limits.maxLoan}
					presets={overview.limits.loanPresets}
					currencySymbol={currencySymbol}
					onChange={reload}
				/>
			)}

			{section === 'cards' && <CardsPanel cards={overview.cards} eligibleAccounts={overview.accounts} onChange={reload} />}

			{section === 'orders' && (
				<StandingOrdersPanel accounts={personalAccounts} currencySymbol={currencySymbol} minIntervalSeconds={overview.limits.minOrderInterval} canCreate />
			)}

			{section === 'tax' && <TaxPanel currencySymbol={currencySymbol} />}
		</RailLayout>
	);
}

interface DashboardProps {
	overview: TbPersonalOverview;
	features: TbFeatureToggles;
	currencySymbol: string;
	colors: TbUiColors;
	onOpenAccount: (account: TbAccount) => void;
	onGo: (section: Section) => void;
}

/** Small "open the page" link in a dashboard panel header. */
function PanelLink({ label, onClick }: { label: string; onClick: () => void }) {
	return (
		<button type="button" className="text-[12px] text-[var(--tb-text-muted)] hover:text-[var(--tb-text-primary)] cursor-pointer" onClick={onClick}>
			{label}
		</button>
	);
}

function Dashboard({ overview, features, currencySymbol, colors, onOpenAccount, onGo }: DashboardProps) {
	const { t, lang } = useTranslation();
	const ownedIds = new Set(overview.accounts.map((account) => account.id));
	const money = (value: number) => formatMoney(value, currencySymbol);
	const weekNet = overview.week.reduce((sum, day) => sum + day.income - day.expenses, 0);
	const loan = overview.loan;

	const quickActions: { key: string; label: string; icon: ReactNode; go: Section; show: boolean }[] = [
		{ key: 'deposit', label: t('actions.deposit'), icon: <DepositIcon width={15} height={15} />, go: 'accounts', show: true },
		{ key: 'withdraw', label: t('actions.withdraw'), icon: <WithdrawIcon width={15} height={15} />, go: 'accounts', show: true },
		{ key: 'transfer', label: t('actions.transfer'), icon: <TransferIcon width={15} height={15} />, go: 'transfer', show: true },
		{ key: 'invoices', label: t('nav.invoices'), icon: <InvoiceIcon width={15} height={15} />, go: 'invoices', show: features.billingEnabled },
		{ key: 'cards', label: t('nav.cards'), icon: <CardIcon width={15} height={15} />, go: 'cards', show: features.cardsEnabled },
	];

	return (
		<>
			<BlurFade>
				<div className="flex items-end justify-between gap-4 flex-wrap">
					<div className="flex flex-col gap-1">
						<span className="text-[11px] uppercase tracking-[0.08em] text-[var(--tb-text-muted)]">{t('stat.total')}</span>
						<NumberTicker value={overview.totalBalance} format={money} className="text-[40px] leading-none font-semibold tabular-nums tracking-tight" />
						<span className="text-xs text-[var(--tb-text-muted)] mt-1">{overview.accounts.length} {t('stat.accounts')}</span>
					</div>
					<StatCard
						label={t('dashboard.weekNet')}
						value={weekNet}
						format={(value) => `${value >= 0 ? '+' : '-'}${money(Math.abs(value))}`}
						tone={weekNet >= 0 ? 'success' : 'danger'}
						hint={
							<Tooltip content={t('dashboard.weekNetHint')}>
								<span className="w-3.5 h-3.5 rounded-full border border-[var(--tb-text-muted)] text-[9px] inline-flex items-center justify-center normal-case cursor-default">?</span>
							</Tooltip>
						}
					/>
				</div>
			</BlurFade>

			<BlurFade delay={0.05}>
				<div className="flex flex-wrap gap-2">
					{quickActions.filter((action) => action.show).map((action) => (
						<button key={action.key} type="button" className={BTN_GHOST} onClick={() => onGo(action.go)}>
							{action.icon} {action.label}
						</button>
					))}
				</div>
			</BlurFade>

			<div className="grid [grid-template-columns:repeat(auto-fill,minmax(210px,1fr))] gap-3">
				{overview.accounts.map((account, index) => (
					<BlurFade key={account.id} delay={0.1 + index * 0.05}>
						<AccountTile account={account} currencySymbol={currencySymbol} onSelect={onOpenAccount} />
					</BlurFade>
				))}
			</div>

			<div className="grid [grid-template-columns:1fr_1.15fr] gap-3 max-[720px]:grid-cols-1">
				<BlurFade delay={0.2} className="min-w-0">
					<section className={`${PANEL} h-full`}>
						<h2 className={PANEL_TITLE}>{t('chart.week')}</h2>
						<WeekGraph points={overview.week} colors={colors} currencySymbol={currencySymbol} />
					</section>
				</BlurFade>

				<BlurFade delay={0.25} className="min-w-0">
					<section className={`${PANEL} h-full`}>
						<div className="flex items-center justify-between">
							<h2 className={PANEL_TITLE}>{t('tx.title')}</h2>
							<PanelLink label={t('tx.all')} onClick={() => onGo('transactions')} />
						</div>
						<TxList transactions={overview.latestTransactions.slice(0, 5)} ownedIds={ownedIds} currencySymbol={currencySymbol} />
					</section>
				</BlurFade>
			</div>

			{(features.cardsEnabled || features.loansEnabled) && (
				<div className="grid [grid-template-columns:1fr_1fr] gap-3 max-[720px]:grid-cols-1">
					{features.cardsEnabled && (
						<BlurFade delay={0.3} className="min-w-0">
							<section className={`${PANEL} h-full`}>
								<div className="flex items-center justify-between">
									<h2 className={PANEL_TITLE}>{t('nav.cards')}</h2>
									<PanelLink label={t('dashboard.manage')} onClick={() => onGo('cards')} />
								</div>
								{overview.cards.length === 0 && <p className={NOTE}>{t('card.none')}</p>}
								<div className="flex flex-col">
									{overview.cards.map((card) => {
										const tone = card.status === 'blocked' ? 'danger' : card.isLocked ? 'warning' : 'success';
										const status = card.status === 'blocked' ? t('card.statusBlocked') : card.isLocked ? t('card.statusLocked') : t('card.statusActive');

										return (
											<div key={card.id} className="flex items-center gap-3 py-2.5 border-b border-[var(--tb-secondary)]/60 last:border-b-0">
												<span className="w-8 h-5 rounded-[4px] bg-[linear-gradient(135deg,var(--tb-accent),color-mix(in_srgb,var(--tb-accent)_40%,var(--tb-primary)))] shrink-0" />
												<div className="flex flex-col gap-0.5 min-w-0 flex-1">
													<span className="text-[13px] truncate">{card.accountName}</span>
													<span className="text-[11px] tabular-nums text-[var(--tb-text-muted)]">{card.maskedNumber}</span>
												</div>
												<span className={BADGE[tone]}>{status}</span>
											</div>
										);
									})}
								</div>
							</section>
						</BlurFade>
					)}

					{features.loansEnabled && (
						<BlurFade delay={0.35} className="min-w-0">
							<section className={`${PANEL} h-full`}>
								<div className="flex items-center justify-between">
									<h2 className={PANEL_TITLE}>{t('loan.title')}</h2>
									<PanelLink label={loan ? t('loan.repay') : t('loan.request')} onClick={() => onGo('loans')} />
								</div>
								{loan ? (
									<div className="flex flex-col gap-3">
										<div className="flex flex-col gap-0.5">
											<span className="text-[11px] uppercase tracking-[0.08em] text-[var(--tb-text-muted)]">{t('loan.remaining')}</span>
											<NumberTicker value={loan.remainingBalance} format={money} className="text-[22px] font-semibold tabular-nums tracking-tight leading-none" />
										</div>
										<div className="flex items-center justify-between gap-3 text-[13px]">
											<span className="text-[var(--tb-text-muted)]">{t('loan.nextInstallment')}</span>
											<span className="tabular-nums">{money(loan.installmentAmount)} · {formatDate(loan.nextPaymentDue, lang)}</span>
										</div>
										{loan.missedPayments > 0 && <p className={FORM_ERROR}>{loan.missedPayments} {t('loan.missed')}</p>}
									</div>
								) : (
									<p className={NOTE}>{t('loan.none')} {t('loan.max', { amount: money(overview.limits.maxLoan) })}</p>
								)}
							</section>
						</BlurFade>
					)}
				</div>
			)}
		</>
	);
}

interface AccountsProps {
	overview: TbPersonalOverview;
	selected: TbAccount;
	onSelect: (account: TbAccount) => void;
	currencySymbol: string;
	features: TbFeatureToggles;
	reload: () => void;
}

function Accounts({ overview, selected, onSelect, currencySymbol, features, reload }: AccountsProps) {
	const { t } = useTranslation();
	const [name, setName] = useState(selected.name);
	const [newName, setNewName] = useState('');
	const [newType, setNewType] = useState<'personal' | 'savings'>('personal');
	const [confirmClose, setConfirmClose] = useState(false);
	const [error, setError] = useState<string | undefined>(undefined);
	const [busy, setBusy] = useState(false);

	const personalCount = overview.accounts.filter((account) => account.type === 'personal').length;
	const savingsCount = overview.accounts.filter((account) => account.type === 'savings').length;
	const canCreatePersonal = personalCount < overview.limits.maxAccounts;
	const canCreateSavings = features.savingsEnabled && savingsCount < overview.limits.maxSavings;
	const lock = useSavingsLock(selected);
	const locked = lock.locked;
	const lockDuration = durationLabel(overview.limits.savingsLockSeconds, t);
	const hasLockPeriod = overview.limits.savingsLockSeconds > 0;
	const newFee = newType === 'savings' ? overview.limits.savingsPrice : overview.limits.newAccountPrice;
	const feeShare = Math.min(1, Math.max(0, overview.limits.feeToBalance ?? 0));
	const feeCredited = Math.floor(newFee * feeShare);

	async function run(action: () => Promise<ActionResult>) {
		setBusy(true);
		setError(undefined);

		const result = await action();

		setBusy(false);

		if (!result.ok) {
			setError(describeError(result.errorKey, t));
			return false;
		}

		reload();
		return true;
	}

	return (
		<>
			<div className="grid [grid-template-columns:repeat(auto-fill,minmax(210px,1fr))] gap-3">
				{overview.accounts.map((account, index) => (
					<BlurFade key={account.id} delay={index * 0.04}>
						<AccountTile
							account={account}
							currencySymbol={currencySymbol}
							selected={account.id === selected.id}
							onSelect={(picked) => {
								onSelect(picked);
								setName(picked.name);
								setConfirmClose(false);
							}}
						/>
					</BlurFade>
				))}
			</div>

			<BlurFade delay={0.12}>
				<section className={PANEL}>
					<div className="flex items-baseline justify-between gap-3 flex-wrap">
						<h2 className="m-0 text-[15px] font-semibold flex items-center gap-2">
							{selected.name}
							{selected.isDefault && (
								<Tooltip content={t('account.esxLinkedHint')}>
									<span className={`${BADGE.accent} inline-flex items-center gap-1 cursor-default`}><StarIcon width={10} height={10} /> {t('account.esxLinked')}</span>
								</Tooltip>
							)}
							{selected.type === 'savings' && (
								<Tooltip content={t('account.lockHint')}>
									<span className={`${locked ? BADGE.warning : BADGE.accent} inline-flex items-center gap-1`}>
										{locked && <LockIcon width={10} height={10} />} {lock.text}
									</span>
								</Tooltip>
							)}
						</h2>
						<span className="text-xs tabular-nums text-[var(--tb-text-muted)]">{selected.number}</span>
					</div>
					{selected.type === 'savings' && (
						<p className={NOTE}>
							{t('account.savingsNote', { rate: selected.interestRate ?? 0, interval: intervalLabel(overview.limits.savingsIntervalSeconds, t) })}
							{hasLockPeriod ? ` ${t('account.savingsLockNote', { duration: lockDuration })}` : ''}
						</p>
					)}
					{error && <p className={FORM_ERROR}>{error}</p>}

					<MoneyActions
						canWithdraw={!locked}
						onDeposit={(amount) => fetchNui('tiltann_banking:ui:personal:deposit', { accountId: selected.id, amount })}
						onWithdraw={(amount) => fetchNui('tiltann_banking:ui:personal:withdraw', { accountId: selected.id, amount })}
						onSuccess={reload}
					/>

					<div className="flex flex-wrap gap-2 items-center pt-2 border-t border-[var(--tb-secondary)]/60">
						<input className={`${INPUT} max-w-[260px]`} type="text" maxLength={25} value={name} onChange={(e) => setName(e.target.value)} disabled={busy} />
						<button type="button" className={BTN_GHOST} onClick={() => run(() => fetchNui('tiltann_banking:ui:personal:renameAccount', { accountId: selected.id, name }))} disabled={busy || name.trim() === '' || name === selected.name}>
							{t('account.rename')}
						</button>
						{selected.type === 'personal' && !selected.isDefault && (
							<Tooltip content={t('account.defaultHint')}>
								<button type="button" className={BTN_GHOST} onClick={() => run(() => fetchNui('tiltann_banking:ui:personal:setDefault', { accountId: selected.id }))} disabled={busy}>
									<StarIcon width={14} height={14} /> {t('account.setDefault')}
								</button>
							</Tooltip>
						)}
						{!selected.isDefault && !confirmClose && (
							<button type="button" className={`${BTN_DANGER} ml-auto`} onClick={() => setConfirmClose(true)} disabled={busy || locked}>
								<TrashIcon width={14} height={14} /> {t('account.delete')}
							</button>
						)}
						{confirmClose && (
							<div className="flex items-center gap-2 flex-wrap basis-full">
								<span className="text-xs text-[var(--tb-text-muted)] flex-1">{t('account.deleteConfirm')}</span>
								<button
									type="button"
									className={BTN_DANGER}
									onClick={async () => {
										const ok = await run(() => fetchNui('tiltann_banking:ui:personal:deleteAccount', { accountId: selected.id }));
										if (ok) {
											setConfirmClose(false);
											onSelect(overview.accounts.find((account) => account.isDefault) ?? overview.accounts[0]);
										}
									}}
									disabled={busy}
								>
									{t('common.confirm')}
								</button>
								<button type="button" className={BTN_GHOST} onClick={() => setConfirmClose(false)} disabled={busy}>{t('common.cancel')}</button>
							</div>
						)}
					</div>
				</section>
			</BlurFade>

			{(canCreatePersonal || canCreateSavings) && (
				<BlurFade delay={0.18}>
					<section className={PANEL}>
						<h2 className={PANEL_TITLE}><PlusIcon width={14} height={14} /> {t('account.new')}</h2>
						<div className="flex flex-wrap gap-2 items-stretch">
							<input className={INPUT} type="text" maxLength={25} placeholder={t('account.namePlaceholder')} value={newName} onChange={(e) => setNewName(e.target.value)} disabled={busy} />
							<select className={SELECT} value={newType} onChange={(e) => setNewType(e.target.value as 'personal' | 'savings')} disabled={busy}>
								{canCreatePersonal && <option value="personal">{t('account.personal')}</option>}
								{canCreateSavings && <option value="savings">{t('account.savings')}</option>}
							</select>
							<button
								type="button"
								className={BTN_PRIMARY}
								onClick={async () => {
									const ok = await run(() => fetchNui('tiltann_banking:ui:personal:createAccount', { name: newName.trim(), accountType: newType }));
									if (ok) setNewName('');
								}}
								disabled={busy || newName.trim() === ''}
							>
								{t('account.create')}
							</button>
						</div>
						<p className={NOTE}>
							{t('account.limitNote', { count: personalCount, max: overview.limits.maxAccounts })}
							{' · '}
							{t('account.fee', { amount: formatMoney(newFee, currencySymbol) })}
							{feeCredited > 0 ? ` ${t(feeShare === 0.5 ? 'account.feeShareHalf' : feeShare === 1 ? 'account.feeShareAll' : 'account.feeShareSome', { percent: Math.round(feeShare * 100), amount: formatMoney(feeCredited, currencySymbol) })}` : ''}
							{newType === 'savings' ? ` · ${t('account.savingsEarns', { rate: overview.limits.savingsRate, interval: intervalLabel(overview.limits.savingsIntervalSeconds, t) })}${hasLockPeriod ? `. ${t('account.savingsLockNote', { duration: lockDuration })}` : ''}` : ''}
						</p>
					</section>
				</BlurFade>
			)}
		</>
	);
}

interface TransferProps {
	accounts: TbAccount[];
	currencySymbol: string;
	reload: () => void;
}

function Transfer({ accounts, currencySymbol, reload }: TransferProps) {
	const { t } = useTranslation();
	const [fromId, setFromId] = useState(accounts.find((account) => account.isDefault)?.id ?? accounts[0]?.id ?? 0);
	const [recipient, setRecipient] = useState('');
	const [amount, setAmount] = useState('');
	const [note, setNote] = useState('');
	const [error, setError] = useState<string | undefined>(undefined);
	const [busy, setBusy] = useState(false);

	const from = accounts.find((account) => account.id === fromId);
	const fromLock = useSavingsLock(from ?? { type: 'personal', lockedUntil: null });
	const fromLocked = fromLock.locked;

	async function submit() {
		const parsed = Math.floor(Number(amount));

		if (!parsed || parsed <= 0 || recipient.trim() === '') {
			return;
		}

		setBusy(true);
		setError(undefined);

		const result = await fetchNui<ActionResult>('tiltann_banking:ui:personal:transfer', { fromAccountId: fromId, recipient: recipient.trim(), amount: parsed, note: note.trim() });

		setBusy(false);

		if (!result.ok) {
			setError(describeError(result.errorKey, t));
			return;
		}

		setRecipient('');
		setAmount('');
		setNote('');
		reload();
	}

	return (
		<BlurFade>
			<section className={`${PANEL} max-w-[560px]`}>
				{error && <p className={FORM_ERROR}>{error}</p>}

				<label className={FIELD_LABEL}>
					{t('account.selectFrom')}
					<select className={SELECT} value={fromId} onChange={(e) => setFromId(Number(e.target.value))} disabled={busy}>
						{accounts.map((account) => (
							<option key={account.id} value={account.id}>{`${account.name} · ${formatMoney(account.balance, currencySymbol)}`}</option>
						))}
					</select>
				</label>
				{fromLocked && from?.lockedUntil && (
					<p className={`${NOTE} text-[var(--tb-warning)]`}>{fromLock.text}</p>
				)}

				<label className={FIELD_LABEL}>
					{t('actions.recipient')}
					<input className={INPUT} type="text" list="tb-own-accounts" title={t('recipient.hint')} value={recipient} onChange={(e) => setRecipient(e.target.value)} disabled={busy} />
					<datalist id="tb-own-accounts">
						{accounts.filter((account) => account.id !== fromId).map((account) => (
							<option key={account.id} value={account.number}>{account.name}</option>
						))}
					</datalist>
					<span className={NOTE}>{t('recipient.hint')}</span>
				</label>

				<div className="grid [grid-template-columns:1fr_2fr] gap-2 max-[560px]:grid-cols-1">
					<label className={FIELD_LABEL}>
						{t('common.amount')}
						<input className={INPUT} type="number" min={1} max={from?.balance} value={amount} onChange={(e) => setAmount(e.target.value)} disabled={busy} />
					</label>
					<label className={FIELD_LABEL}>
						{t('common.note')}
						<input className={INPUT} type="text" maxLength={100} value={note} onChange={(e) => setNote(e.target.value)} disabled={busy} />
					</label>
				</div>

				<button type="button" className={`${BTN_PRIMARY} self-start`} onClick={submit} disabled={busy || fromLocked || recipient.trim() === '' || amount === ''}>
					<TransferIcon width={14} height={14} /> {t('actions.send')}
				</button>
			</section>
		</BlurFade>
	);
}

function Transactions({ accounts, currencySymbol, features, reload }: { accounts: TbAccount[]; currencySymbol: string; features: TbFeatureToggles; reload: () => void }) {
	const { t } = useTranslation();
	const [accountId, setAccountId] = useState(accounts[0]?.id ?? 0);
	const [filters, setFilters] = useState<TbTransactionFilters | undefined>(undefined);
	const [version, setVersion] = useState(0);

	function cleared() {
		setVersion((v) => v + 1);
		reload();
	}

	return (
		<BlurFade>
			<section className={PANEL}>
				<select className={`${SELECT} self-start`} value={accountId} onChange={(e) => setAccountId(Number(e.target.value))} aria-label={t('nav.accounts')}>
					{accounts.map((account) => (
						<option key={account.id} value={account.id}>{`${account.name} · ${account.number}`}</option>
					))}
				</select>
				<TransactionFilters onChange={setFilters} />
				{features.clearHistoryEnabled && <ClearHistoryButton key={accountId} endpoint="tiltann_banking:ui:personal:clearHistory" accountId={accountId} onCleared={cleared} />}
				<TransactionTable key={`${accountId}:${version}`} accountId={accountId} currencySymbol={currencySymbol} filters={filters} />
			</section>
		</BlurFade>
	);
}
