import { useState } from 'react';
import type { ActionResult, TbAccount, TbCardSummary } from '../types';
import { fetchNui } from '../api/nui';
import { describeError } from '../errorMessages';
import { useTranslation } from '../i18n/context';
import { AlertIcon, CardIcon, LockIcon, TrashIcon, UnlockIcon } from '../icons';
import { BADGE, BTN_DANGER, BTN_GHOST, BTN_PRIMARY, FORM_ERROR, INPUT, NOTE, PANEL } from '../ui-classes';

interface CardItemProps {
	card: TbCardSummary;
	onChange: () => void;
}

/** One held card: status badge, set/change PIN, lock/unlock, report lost. */
export function CardItem({ card, onChange }: CardItemProps) {
	const { t } = useTranslation();
	const [busy, setBusy] = useState(false);
	const [error, setError] = useState<string | undefined>(undefined);
	const [pinOpen, setPinOpen] = useState(!card.hasPin);
	const [pin, setPin] = useState('');
	const [confirmingLost, setConfirmingLost] = useState(false);
	const [confirmingDelete, setConfirmingDelete] = useState(false);

	async function run(action: () => Promise<ActionResult>) {
		setBusy(true);
		setError(undefined);

		const result = await action();

		setBusy(false);

		if (!result.ok) {
			setError(describeError(result.errorKey, t));
			return false;
		}

		onChange();
		return true;
	}

	async function setCardPin() {
		if (pin.length === 0) {
			return;
		}

		const ok = await run(() => fetchNui('tiltann_banking:ui:cards:setPin', { cardId: card.id, pin }));

		if (ok) {
			setPin('');
			setPinOpen(false);
		}
	}

	const tone = card.status === 'blocked' ? 'danger' : card.isLocked ? 'warning' : 'success';
	const statusLabel = card.status === 'blocked' ? t('card.statusBlocked') : card.isLocked ? t('card.statusLocked') : t('card.statusActive');

	return (
		<div className="flex flex-col gap-2.5 py-3 border-b border-[var(--tb-secondary)]/60 last:border-b-0">
			<div className="flex items-center justify-between gap-3 flex-wrap">
				<div className="flex flex-col gap-0.5">
					<span className="text-[13px] font-medium">
						{card.accountName} {card.isCompany && <span className={`${BADGE.neutral} ml-1`}>{t('card.company')}</span>}
					</span>
					<span className="tabular-nums text-[15px] tracking-wide">{card.maskedNumber}</span>
				</div>
				<span className={BADGE[tone]}>{statusLabel}</span>
			</div>

			{!card.hasPin && <p className={NOTE}>{t('card.needsPin')}</p>}
			{error && <p className={FORM_ERROR}>{error}</p>}

			{pinOpen && (
				<div className="flex flex-wrap gap-2.5 items-center">
					<input
						className={INPUT}
						type="password"
						inputMode="numeric"
						maxLength={6}
						placeholder={t('card.pinPlaceholder')}
						value={pin}
						onChange={(event) => setPin(event.target.value.replace(/\D/g, ''))}
						disabled={busy}
					/>
					<button type="button" className={BTN_PRIMARY} onClick={setCardPin} disabled={busy || pin.length === 0}>
						{t('card.setPin')}
					</button>
					{card.hasPin && (
						<button type="button" className={BTN_GHOST} onClick={() => setPinOpen(false)} disabled={busy}>
							{t('common.cancel')}
						</button>
					)}
				</div>
			)}

			<div className="flex items-center gap-2.5 flex-wrap">
				{card.hasPin && !pinOpen && (
					<button type="button" className={BTN_GHOST} onClick={() => setPinOpen(true)} disabled={busy}>
						{t('card.changePin')}
					</button>
				)}
				<button
					type="button"
					className={BTN_GHOST}
					onClick={() => run(() => fetchNui('tiltann_banking:ui:cards:toggleLock', { cardId: card.id }))}
					disabled={busy || card.status === 'blocked'}
				>
					{card.isLocked ? <UnlockIcon width={14} height={14} /> : <LockIcon width={14} height={14} />}
					{card.isLocked ? t('card.unlock') : t('card.lock')}
				</button>

				{/* Lost = pay the fee and get a replacement immediately.
				    Delete = free, destroys the card and leaves the account
				    without one until a new card is requested. Two different
				    intentions, so two buttons rather than one overloaded one. */}
				{!confirmingLost && !confirmingDelete && (
					<button type="button" className={BTN_GHOST} onClick={() => setConfirmingDelete(true)} disabled={busy}>
						<TrashIcon width={14} height={14} /> {t('card.delete')}
					</button>
				)}

				{confirmingDelete && (
					<>
						<span className="text-xs text-[var(--tb-text-muted)]">{t('card.confirmDelete')}</span>
						<button
							type="button"
							className={BTN_DANGER}
							onClick={async () => {
								await run(() => fetchNui('tiltann_banking:ui:cards:delete', { cardId: card.id }));
								setConfirmingDelete(false);
							}}
							disabled={busy}
						>
							{t('common.confirm')}
						</button>
						<button type="button" className={BTN_GHOST} onClick={() => setConfirmingDelete(false)} disabled={busy}>
							{t('common.cancel')}
						</button>
					</>
				)}

				{!confirmingLost && !confirmingDelete ? (
					<button type="button" className={BTN_DANGER} onClick={() => setConfirmingLost(true)} disabled={busy}>
						<AlertIcon width={14} height={14} /> {t('card.reportLost')}
					</button>
				) : confirmingLost ? (
					<>
						<span className="text-xs text-[var(--tb-text-muted)]">{t('card.confirmLost')}</span>
						<button
							type="button"
							className={BTN_DANGER}
							onClick={async () => {
								await run(() => fetchNui('tiltann_banking:ui:cards:reportLost', { cardId: card.id }));
								setConfirmingLost(false);
							}}
							disabled={busy}
						>
							{t('common.confirm')}
						</button>
						<button type="button" className={BTN_GHOST} onClick={() => setConfirmingLost(false)} disabled={busy}>
							{t('common.cancel')}
						</button>
					</>
				) : null}
			</div>
		</div>
	);
}

interface RequestCardButtonProps {
	accountId: number;
	label: string;
	onChange: () => void;
}

/** "Get a card" for one account that doesn't have one yet. */
export function RequestCardButton({ accountId, label, onChange }: RequestCardButtonProps) {
	const { t } = useTranslation();
	const [busy, setBusy] = useState(false);
	const [error, setError] = useState<string | undefined>(undefined);

	async function request() {
		setBusy(true);
		setError(undefined);

		const result = await fetchNui<ActionResult>('tiltann_banking:ui:cards:request', { accountId });

		setBusy(false);

		if (!result.ok) {
			setError(describeError(result.errorKey, t));
			return;
		}

		onChange();
	}

	return (
		<div className="flex items-center justify-between gap-3 py-3 border-b border-[var(--tb-secondary)]/60 last:border-b-0 flex-wrap">
			<span className="text-[13px]">
				<span className="text-[var(--tb-text-muted)]">{t('card.forAccount')}</span> {label}
			</span>
			<div className="flex items-center gap-2.5">
				{error && <span className={FORM_ERROR}>{error}</span>}
				<button type="button" className={BTN_PRIMARY} onClick={request} disabled={busy}>
					<CardIcon width={14} height={14} /> {busy ? t('card.requesting') : t('card.request')}
				</button>
			</div>
		</div>
	);
}

interface CardsPanelProps {
	cards: TbCardSummary[];
	eligibleAccounts: TbAccount[];
	onChange: () => void;
}

/** The Personal tab's Cards page: every held card plus a request row per personal account without one. */
export function CardsPanel({ cards, eligibleAccounts, onChange }: CardsPanelProps) {
	const { t } = useTranslation();
	const withoutCard = eligibleAccounts.filter((account) => account.type === 'personal' && !cards.some((card) => card.accountId === account.id));

	return (
		<section className={PANEL}>
			{cards.length === 0 && withoutCard.length === 0 && <p className={NOTE}>{t('card.none')}</p>}
			<div className="flex flex-col">
				{cards.map((card) => (
					<CardItem key={card.id} card={card} onChange={onChange} />
				))}
				{withoutCard.map((account) => (
					<RequestCardButton key={account.id} accountId={account.id} label={`${account.name} · ${account.number}`} onChange={onChange} />
				))}
			</div>
		</section>
	);
}
