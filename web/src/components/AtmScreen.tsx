import { useEffect, useRef, useState } from 'react';
import { motion } from 'motion/react';
import type { ActionResult, AtmOpenPayload, TbAccount, TbAtmKey, TbAtmSession, TbCardSummary } from '../types';
import { fetchNui } from '../api/nui';
import { describeError } from '../errorMessages';
import { useTranslation } from '../i18n/context';
import { readStoredAccent } from '../state/accent';
import { formatMoney } from '../format';
import { ICON_BTN } from '../ui-classes';
import { CardIcon, ChevronRightIcon, CloseIcon, UnlockIcon } from '../icons';
import { SettingsPanel } from './SettingsPanel';
import { NumberTicker } from './ui/NumberTicker';

interface AtmScreenProps {
	payload: AtmOpenPayload;
	onClose: () => void;
}

const SCREEN_BTN = 'inline-flex items-center justify-center gap-2 rounded-xl border border-[var(--tb-secondary)] bg-[var(--tb-surface)] text-[var(--tb-text-primary)] font-semibold cursor-pointer transition-all hover:border-[var(--tb-accent)] hover:text-[var(--tb-accent)] active:scale-[0.97] disabled:opacity-40 disabled:cursor-default';
const CONFIRM_BTN = '!bg-[var(--tb-accent)] !border-[var(--tb-accent)] !text-[var(--tb-primary)] hover:!text-[var(--tb-primary)] hover:!opacity-90';

type Step = { kind: 'pick' } | { kind: 'gate'; card: TbCardSummary } | { kind: 'session'; key: TbAtmKey; session: TbAtmSession };

/**
 * A real street ATM: pick a card, enter its PIN, then withdraw or deposit on
 * that card's account. Deliberately its own small screen, no tabs, no Business
 * dashboard; those live at the bank terminal. With Config.Cards.Enabled
 * off there's no card system to gate behind, so it lists the player's
 * personal accounts directly instead.
 */
export function AtmScreen({ payload, onClose }: AtmScreenProps) {
	const { t } = useTranslation();
	const [accent, setAccent] = useState(() => readStoredAccent() ?? payload.colors.accent);
	const [step, setStep] = useState<Step>({ kind: 'pick' });
	const [cards, setCards] = useState(payload.atm.cards);
	const [error, setError] = useState<string | undefined>(undefined);
	const [busy, setBusy] = useState(false);

	const stepRef = useRef(step);
	stepRef.current = step;

	// The game says a balance changed elsewhere: re-fetch the open session
	// with the key we already hold, so the PIN unlock stays valid.
	useEffect(() => {
		const onRefresh = async () => {
			const current = stepRef.current;

			if (current.kind !== 'session') {
				return;
			}

			const result = await fetchNui<{ ok: boolean; session?: TbAtmSession }>('tiltann_banking:ui:atm:getSession', { key: current.key });

			if (result.ok && result.session) {
				const session = result.session;
				setStep((now) => (now.kind === 'session' && now.key === current.key ? { kind: 'session', key: current.key, session } : now));
			}
		};

		window.addEventListener('tb:refresh', onRefresh);
		return () => window.removeEventListener('tb:refresh', onRefresh);
	}, []);

	function handleClose() {
		fetchNui('tiltann_banking:ui:close');
		onClose();
	}

	async function openSession(key: TbAtmKey) {
		const result = await fetchNui<{ ok: boolean; errorKey?: string; session?: TbAtmSession }>('tiltann_banking:ui:atm:getSession', { key });

		if (!result.ok || !result.session) {
			setError(describeError(result.errorKey, t));
			return;
		}

		setError(undefined);
		setStep({ kind: 'session', key, session: result.session });
	}

	async function unlock(card: TbCardSummary, pin: string) {
		const result = await fetchNui<{ ok: boolean; errorKey?: string; session?: TbAtmSession }>('tiltann_banking:ui:atm:unlock', { cardId: card.id, pin });

		if (!result.ok || !result.session) {
			setError(describeError(result.errorKey, t));
			return { ok: false };
		}

		setError(undefined);
		setStep({ kind: 'session', key: { cardId: card.id }, session: result.session });
		return { ok: true };
	}

	async function toggleLock(card: TbCardSummary) {
		setBusy(true);
		const result = await fetchNui<ActionResult<boolean>>('tiltann_banking:ui:cards:toggleLock', { cardId: card.id });
		setBusy(false);

		if (!result.ok) {
			setError(describeError(result.errorKey, t));
			return;
		}

		const updated = { ...card, isLocked: result.value === true };
		setCards((current) => current.map((entry) => (entry.id === card.id ? updated : entry)));
		setStep({ kind: 'gate', card: updated });
	}

	function pickCard(card: TbCardSummary) {
		setError(undefined);
		setStep({ kind: 'gate', card });
	}

	return (
		<motion.div
			initial={{ opacity: 0, y: 18, scale: 0.985 }}
			animate={{ opacity: 1, y: 0, scale: 1 }}
			exit={{ opacity: 0, y: 24, scale: 0.97, transition: { duration: 0.18, ease: 'easeIn' } }}
			transition={{ type: 'spring', stiffness: 260, damping: 30 }}
			className="w-[min(440px,94vw)] mx-auto mt-[6vh] max-h-[90vh] rounded-[30px] bg-[linear-gradient(180deg,#2a2c33_0%,#15161a_100%)] p-3 shadow-[0_30px_70px_rgba(0,0,0,0.55),inset_0_1px_0_rgba(255,255,255,0.06)]"
		>
			<div className="bg-[var(--tb-primary)] rounded-[22px] flex flex-col overflow-hidden">
				<header className="flex items-center justify-between px-5 pt-4 pb-2 shrink-0">
					<span className="flex items-center gap-2 text-[13px] font-semibold tracking-[0.2em] text-[var(--tb-text-muted)]">
						<CardIcon width={16} height={16} className="text-[var(--tb-accent)]" /> ATM
					</span>
					<div className="flex items-center gap-1">
						<SettingsPanel accent={accent} onAccentChange={setAccent} />
						<button type="button" className={ICON_BTN} onClick={handleClose} aria-label={t('common.close')}>
							<CloseIcon width={16} height={16} />
						</button>
					</div>
				</header>
				<div className="mx-5 h-px bg-[linear-gradient(90deg,transparent,var(--tb-accent),transparent)] opacity-60" />

				<div data-tb-scroll className="px-5 pb-5 pt-2 flex flex-col gap-4 min-h-[400px] max-h-[75vh] overflow-y-auto">
					{step.kind !== 'pick' && (
						<button type="button" className={`${SCREEN_BTN} self-start !py-1.5 !px-3 text-[13px]`} onClick={() => { setError(undefined); setStep({ kind: 'pick' }); }}>
							{t('atm.changeCard')}
						</button>
					)}

					{error && <p className="m-0 text-center text-[13px] text-[var(--tb-danger)]">{error}</p>}

			{step.kind === 'pick' && (
				<PickList
					cardsEnabled={payload.atm.cardsEnabled}
					cards={cards}
					accounts={payload.atm.accounts}
					currencySymbol={payload.currencySymbol}
					onPickCard={pickCard}
					onPickAccount={(account) => openSession({ accountId: account.id })}
				/>
			)}

			{step.kind === 'gate' && (
				<CardGate card={step.card} busy={busy} onUnlockCard={() => toggleLock(step.card)} onSubmitPin={(pin) => unlock(step.card, pin)} />
			)}

			{step.kind === 'session' && (
				<Session
					session={step.session}
					atmKey={step.key}
					currencySymbol={payload.currencySymbol}
					onRefresh={() => openSession(step.key)}
				/>
			)}
				</div>
			</div>

		</motion.div>
	);
}

const PICK_ROW = 'flex items-center gap-3 text-left rounded-xl border border-[var(--tb-secondary)] bg-[var(--tb-surface)] px-4 py-3.5 cursor-pointer transition-all hover:border-[var(--tb-accent)]';
const MUTED = 'text-[var(--tb-text-muted)]';
const BADGE_CLS = 'rounded-md border border-current px-1.5 py-0.5 text-[11px]';

interface PickListProps {
	cardsEnabled: boolean;
	cards: TbCardSummary[];
	accounts: TbAccount[];
	currencySymbol: string;
	onPickCard: (card: TbCardSummary) => void;
	onPickAccount: (account: TbAccount) => void;
}

function PickList({ cardsEnabled, cards, accounts, currencySymbol, onPickCard, onPickAccount }: PickListProps) {
	const { t } = useTranslation();

	if (cardsEnabled) {
		return (
			<div className="flex flex-col gap-3">
				<h2 className="m-0 text-center text-lg font-semibold">{t('atm.pickCard')}</h2>
				{cards.length === 0 && <p className={`m-0 text-center text-sm ${MUTED}`}>{t('atm.noCards')}</p>}
				<div className="flex flex-col gap-2.5">
					{cards.map((card) => (
						<button key={card.id} type="button" onClick={() => onPickCard(card)} className={PICK_ROW}>
							<span className="w-11 h-7 rounded-[5px] bg-[linear-gradient(135deg,var(--tb-accent),color-mix(in_srgb,var(--tb-accent)_40%,#000))] shrink-0" />
							<div className="flex flex-col gap-0.5 min-w-0 flex-1">
								<span className="text-[15px] font-semibold truncate">{card.accountName}</span>
								<span className={`tabular-nums text-xs ${MUTED}`}>{card.maskedNumber}</span>
							</div>
							<div className="flex gap-1.5">
								{card.isCompany && <span className={BADGE_CLS}>{t('atm.company')}</span>}
								{card.status === 'blocked' && <span className={`${BADGE_CLS} text-[var(--tb-danger)]`}>{t('atm.blocked')}</span>}
								{card.status !== 'blocked' && card.isLocked && <span className={`${BADGE_CLS} text-[var(--tb-warning)]`}>{t('atm.locked')}</span>}
							</div>
							<ChevronRightIcon width={16} height={16} className={`${MUTED} shrink-0`} />
						</button>
					))}
				</div>
			</div>
		);
	}

	return (
		<div className="flex flex-col gap-3">
			<h2 className="m-0 text-center text-lg font-semibold">{t('atm.pickAccount')}</h2>
			<div className="flex flex-col gap-2.5">
				{accounts.map((account) => (
					<button key={account.id} type="button" onClick={() => onPickAccount(account)} className={PICK_ROW}>
						<div className="flex flex-col gap-0.5 min-w-0 flex-1">
							<span className="text-[15px] font-semibold truncate">{account.name}</span>
							<span className={`tabular-nums text-xs ${MUTED}`}>{account.number}</span>
						</div>
						<span className="tabular-nums font-semibold">{formatMoney(account.balance, currencySymbol)}</span>
						<ChevronRightIcon width={16} height={16} className={`${MUTED} shrink-0`} />
					</button>
				))}
			</div>
		</div>
	);
}

interface KeypadProps {
	title: string;
	subtitle?: string;
	maxLength: number;
	masked: boolean;
	confirmLabel: string;
	errorText?: string;
	onSubmit: (value: string) => Promise<{ ok: boolean }>;
	onCancel?: () => void;
}

const KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'clear', '0', 'back'];

/** On-screen numeric keypad, used for the PIN and for typed amounts. */
function Keypad({ title, subtitle, maxLength, masked, confirmLabel, errorText, onSubmit, onCancel }: KeypadProps) {
	const { t } = useTranslation();
	const [value, setValue] = useState('');
	const [submitting, setSubmitting] = useState(false);

	function press(key: string) {
		if (submitting) {
			return;
		}

		if (key === 'back') {
			setValue((current) => current.slice(0, -1));
		} else if (key === 'clear') {
			setValue('');
		} else if (value.length < maxLength && !(!masked && value === '' && key === '0')) {
			setValue((current) => current + key);
		}
	}

	useEffect(() => {
		function onKey(event: KeyboardEvent) {
			if (/^[0-9]$/.test(event.key)) {
				press(event.key);
			} else if (event.key === 'Backspace') {
				press('back');
			} else if (event.key === 'Enter') {
				void submit();
			}
		}

		window.addEventListener('keydown', onKey);
		return () => window.removeEventListener('keydown', onKey);
	});

	async function submit() {
		if (value === '' || submitting) {
			return;
		}

		setSubmitting(true);
		const result = await onSubmit(value);
		setSubmitting(false);

		if (!result.ok && masked) {
			setValue('');
		}
	}

	return (
		<div className="flex flex-col items-center gap-3 max-w-[300px] mx-auto w-full">
			<div className="flex flex-col items-center gap-0.5">
				<h2 className="m-0 text-lg font-semibold">{title}</h2>
				{subtitle && <p className={`m-0 text-xs tabular-nums text-center ${MUTED}`}>{subtitle}</p>}
			</div>

			<div className="w-full h-12 rounded-xl bg-[var(--tb-surface)] border border-[var(--tb-accent)]/60 shadow-[0_0_0_3px_color-mix(in_srgb,var(--tb-accent)_12%,transparent)] flex items-center justify-center text-2xl font-semibold tabular-nums tracking-widest">
				{masked ? '•'.repeat(value.length) : value}
			</div>

			{errorText && <p className="m-0 text-center text-[13px] text-[var(--tb-danger)]">{errorText}</p>}

			<div className="grid grid-cols-3 gap-2 w-full">
				{KEYS.map((key) => (
					<button key={key} type="button" className={`${SCREEN_BTN} h-12 text-xl`} onClick={() => press(key)} disabled={submitting}>
						{key === 'back' ? '⌫' : key === 'clear' ? 'C' : key}
					</button>
				))}
			</div>

			<div className="grid grid-cols-2 gap-2 w-full">
				{onCancel ? (
					<button type="button" className={`${SCREEN_BTN} h-12 text-base`} onClick={onCancel} disabled={submitting}>
						{t('common.cancel')}
					</button>
				) : (
					<span />
				)}
				<button type="button" className={`${SCREEN_BTN} ${CONFIRM_BTN} h-12 text-base`} onClick={submit} disabled={value === '' || submitting}>
					{submitting ? t('pin.checking') : confirmLabel}
				</button>
			</div>
		</div>
	);
}

interface CardGateProps {
	card: TbCardSummary;
	busy: boolean;
	onUnlockCard: () => void;
	onSubmitPin: (pin: string) => Promise<{ ok: boolean }>;
}

/** Everything between picking a card and getting a session: blocked / locked / no PIN dead-ends, else the PIN pad. */
function CardGate({ card, busy, onUnlockCard, onSubmitPin }: CardGateProps) {
	const { t } = useTranslation();

	if (card.status === 'blocked') {
		return <p className="m-0 text-center text-[15px] text-[var(--tb-danger)] py-10">{t('atm.blockedMessage')}</p>;
	}

	if (card.isLocked) {
		return (
			<div className="flex flex-col items-center gap-4 py-10">
				<p className={`m-0 text-center text-[15px] ${MUTED}`}>{t('atm.lockedMessage')}</p>
				<button type="button" className={`${SCREEN_BTN} h-12 px-8 text-base`} onClick={onUnlockCard} disabled={busy}>
					<UnlockIcon width={16} height={16} /> {t('card.unlock')}
				</button>
			</div>
		);
	}

	if (!card.hasPin) {
		return <p className={`m-0 text-center text-[15px] py-10 ${MUTED}`}>{t('atm.noPin')}</p>;
	}

	return <Keypad title={t('pin.title')} subtitle={`${card.accountName} · ${card.maskedNumber}`} maxLength={6} masked confirmLabel={t('pin.enter')} onSubmit={onSubmitPin} />;
}

interface SessionProps {
	session: TbAtmSession;
	atmKey: TbAtmKey;
	currencySymbol: string;
	onRefresh: () => void;
}

type Mode = { kind: 'menu' } | { kind: 'amount'; action: 'withdraw' | 'deposit' } | { kind: 'done'; action: 'withdraw' | 'deposit'; amount: number };

function Session({ session, atmKey, currencySymbol, onRefresh }: SessionProps) {
	const { t } = useTranslation();
	const [mode, setMode] = useState<Mode>({ kind: 'menu' });
	const [busyAmount, setBusyAmount] = useState<number | null>(null);
	const [actionError, setActionError] = useState<string | undefined>(undefined);

	const left = Math.max(0, session.dailyLimit - session.withdrawnToday);

	async function run(action: 'withdraw' | 'deposit', amount: number) {
		setBusyAmount(amount);
		setActionError(undefined);

		const result = await fetchNui<ActionResult>(`tiltann_banking:ui:atm:${action}`, { key: atmKey, amount });

		setBusyAmount(null);

		if (!result.ok) {
			setActionError(describeError(result.errorKey, t));
			return { ok: false };
		}

		setMode({ kind: 'done', action, amount });
		onRefresh();
		return { ok: true };
	}

	function goMenu() {
		setActionError(undefined);
		setMode({ kind: 'menu' });
	}

	if (mode.kind === 'amount') {
		return (
			<Keypad
				title={mode.action === 'withdraw' ? t('atm.otherAmount') : t('actions.deposit')}
				subtitle={mode.action === 'withdraw' ? t('actions.dailyLeft', { amount: formatMoney(left, currencySymbol) }) : undefined}
				maxLength={9}
				masked={false}
				confirmLabel={t('common.confirm')}
				errorText={actionError}
				onSubmit={(value) => run(mode.action, Math.floor(Number(value)))}
				onCancel={goMenu}
			/>
		);
	}

	if (mode.kind === 'done') {
		return (
			<div className="flex flex-col items-center justify-center gap-5 py-8 flex-1">
				<p className="m-0 text-xl font-semibold text-center">{mode.action === 'withdraw' ? t('atm.doneWithdraw') : t('atm.doneDeposit')}</p>
				<p className="m-0 text-3xl font-semibold tabular-nums">{formatMoney(mode.amount, currencySymbol)}</p>
				<p className={`m-0 text-sm tabular-nums ${MUTED}`}>{formatMoney(session.account.balance, currencySymbol)}</p>
				<button type="button" className={`${SCREEN_BTN} h-12 px-10 text-base`} onClick={goMenu}>
					{t('atm.done')}
				</button>
			</div>
		);
	}

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-col items-center gap-1 text-center rounded-2xl border border-[var(--tb-accent)]/40 bg-[linear-gradient(180deg,color-mix(in_srgb,var(--tb-accent)_10%,var(--tb-surface)),var(--tb-surface))] px-4 py-5">
				<span className={`text-xs uppercase tracking-[0.12em] ${MUTED}`}>
					{session.account.name}
					{session.isCompany ? ` · ${t('atm.company')}` : ''}
				</span>
				<NumberTicker value={session.account.balance} format={(value) => formatMoney(value, currencySymbol)} className="text-[40px] leading-none font-semibold tabular-nums tracking-tight" />
				<span className={`text-xs tabular-nums ${MUTED}`}>{session.account.number}</span>
			</div>

			{actionError && <p className="m-0 text-center text-[13px] text-[var(--tb-danger)]">{actionError}</p>}

			<div className="flex flex-col gap-2">
				<span className={`text-center text-xs uppercase tracking-[0.12em] ${MUTED}`}>{t('actions.quick')}</span>
				<div className="grid grid-cols-2 gap-2.5">
					{session.quickWithdraw.map((amount) => (
						<button
							key={amount}
							type="button"
							className={`${SCREEN_BTN} h-14 text-xl tabular-nums`}
							onClick={() => run('withdraw', amount)}
							disabled={busyAmount !== null || amount > session.account.balance || amount > left}
						>
							{busyAmount === amount ? '...' : formatMoney(amount, currencySymbol)}
						</button>
					))}
				</div>
			</div>

			<div className="grid grid-cols-2 gap-2.5">
				<button type="button" className={`${SCREEN_BTN} h-14 text-base`} onClick={() => { setActionError(undefined); setMode({ kind: 'amount', action: 'withdraw' }); }} disabled={busyAmount !== null}>
					{t('atm.otherAmount')}
				</button>
				<button type="button" className={`${SCREEN_BTN} h-14 text-base`} onClick={() => { setActionError(undefined); setMode({ kind: 'amount', action: 'deposit' }); }} disabled={busyAmount !== null}>
					{t('actions.deposit')}
				</button>
			</div>

			<p className={`m-0 text-center text-xs tabular-nums ${MUTED}`}>{t('actions.dailyLeft', { amount: formatMoney(left, currencySymbol) })}</p>
		</div>
	);
}
