import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { motion } from 'motion/react';
import type { ActionResult, BillingOpenPayload, TbAccount } from '../types';
import { fetchNui } from '../api/nui';
import { describeError } from '../errorMessages';
import { useTranslation } from '../i18n/context';
import { formatMoney } from '../format';
import { CloseIcon, RefreshIcon } from '../icons';

interface BillingScreenProps {
	payload: BillingOpenPayload;
	onClose: () => void;
}

interface NearbyPlayer {
	id: number;
	name: string;
}

type BillTab = 'personal' | 'business';

const NEARBY_REFRESH_MS = 10000;

// The paper keeps fixed colours so it reads as a sheet on any theme.
const INK = 'text-[#1f3a6e]';
const LINE_INPUT = `w-full bg-transparent border-0 border-b border-[#b9ad92] ${INK} px-1 py-1 text-[14px] font-medium placeholder:text-[#a79d86] placeholder:font-normal focus:outline-none focus:border-[#1f3a6e] disabled:opacity-60`;
const LABEL = 'text-[10px] tracking-[0.14em] uppercase text-[#7a705b] font-semibold';

function accountLabel(account: TbAccount): string {
	const job = account.type === 'society' && account.jobLabel && account.jobLabel !== account.name ? ` (${account.jobLabel})` : '';
	return `${account.name}${job}`;
}

/**
 * The billing window opened with the billing key: a paper invoice pad.
 * Sending only; paying and declining happen at the terminal. Escape is
 * handled in App, which also tells the game to release the NUI focus.
 */
export function BillingScreen({ payload, onClose }: BillingScreenProps) {
	const { t } = useTranslation();
	const { currencySymbol } = payload;
	const maxShare = Math.max(0, Math.floor(payload.billing?.maxSharePercent ?? 0));

	const personalAccounts = useMemo(() => payload.accounts.filter((a) => a.type === 'personal'), [payload.accounts]);
	const societyAccounts = useMemo(() => payload.accounts.filter((a) => a.type === 'society'), [payload.accounts]);

	const [tab, setTab] = useState<BillTab>(personalAccounts.length > 0 || societyAccounts.length === 0 ? 'personal' : 'business');
	const [personalId, setPersonalId] = useState((personalAccounts.find((a) => a.isDefault) ?? personalAccounts[0])?.id ?? 0);
	const [societyId, setSocietyId] = useState(societyAccounts[0]?.id ?? 0);
	const [nearby, setNearby] = useState<NearbyPlayer[]>([]);
	const [recipient, setRecipient] = useState('');
	const [reason, setReason] = useState('');
	const [amount, setAmount] = useState('');
	const [share, setShare] = useState(0);
	const [error, setError] = useState<string | undefined>(undefined);
	const [sent, setSent] = useState(false);
	const [busy, setBusy] = useState(false);
	const [refreshing, setRefreshing] = useState(false);
	const sentTimer = useRef<number | undefined>(undefined);

	// a stable, decorative bill number for this sitting
	const billNumber = useMemo(() => String(Math.floor(100000 + Math.random() * 900000)), []);

	const loadNearby = useCallback(async () => {
		setRefreshing(true);

		try {
			const list = await fetchNui<NearbyPlayer[]>('tiltann_banking:ui:billing:getNearby');
			setNearby(Array.isArray(list) ? list : []);
		} catch {
			setNearby([]);
		}

		setRefreshing(false);
	}, []);

	useEffect(() => {
		loadNearby();
		const timer = window.setInterval(loadNearby, NEARBY_REFRESH_MS);

		return () => {
			window.clearInterval(timer);
			window.clearTimeout(sentTimer.current);
		};
	}, [loadNearby]);

	const isBusiness = tab === 'business';
	const fromAccountId = isBusiness ? societyId : personalId;
	const parsedAmount = Math.floor(Number(amount)) || 0;
	const youGet = isBusiness ? Math.floor((parsedAmount * share) / 100) : parsedAmount;
	const businessGets = parsedAmount - youGet;
	const canSend = !busy && fromAccountId > 0 && recipient.trim() !== '' && parsedAmount > 0;

	async function send() {
		if (!canSend) {
			return;
		}

		setBusy(true);
		setError(undefined);
		setSent(false);

		const result = await fetchNui<ActionResult>('tiltann_banking:ui:billing:send', {
			fromAccountId,
			recipient: recipient.trim(),
			amount: parsedAmount,
			reason: reason.trim(),
			sharePercent: isBusiness ? Math.min(share, maxShare) : 0,
		});

		setBusy(false);

		if (!result.ok) {
			setError(describeError(result.errorKey, t));
			return;
		}

		setAmount('');
		setReason('');
		setSent(true);
		window.clearTimeout(sentTimer.current);
		sentTimer.current = window.setTimeout(() => setSent(false), 4000);
	}

	function handleClose() {
		fetchNui('tiltann_banking:ui:close');
		onClose();
	}

	function tabButton(id: BillTab, label: string, disabled: boolean) {
		const active = tab === id;

		return (
			<button
				type="button"
				disabled={disabled}
				onClick={() => {
					setTab(id);
					setError(undefined);
				}}
				className={`px-4 py-1.5 text-[12px] font-semibold tracking-wide rounded-t-md border border-b-0 transition-colors cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed ${active ? 'bg-[#f7f1e1] border-[#b9ad92] text-[#2b2a28]' : 'bg-[#e6dcc2] border-transparent text-[#7a705b] hover:text-[#2b2a28]'}`}
			>
				{label}
			</button>
		);
	}

	const accountSelect = (accounts: TbAccount[], value: number, onChange: (id: number) => void) =>
		accounts.length > 1 ? (
			<label className="flex flex-col gap-0.5">
				<span className={LABEL}>{t(isBusiness ? 'billing.business' : 'billing.account')}</span>
				<select className={`${LINE_INPUT} cursor-pointer`} value={value} onChange={(e) => onChange(Number(e.target.value))} disabled={busy}>
					{accounts.map((account) => (
						<option key={account.id} value={account.id}>{accountLabel(account)}</option>
					))}
				</select>
			</label>
		) : null;

	return (
		<motion.div
			initial={{ opacity: 0, y: 24, rotate: -2 }}
			animate={{ opacity: 1, y: 0, rotate: -0.6 }}
			exit={{ opacity: 0, y: 24, rotate: -2, transition: { duration: 0.18, ease: 'easeIn' } }}
			transition={{ type: 'spring', stiffness: 240, damping: 26 }}
			className="w-[min(480px,92vw)] mx-auto mt-[5vh] max-h-[88vh] flex flex-col"
		>
			<div className="flex gap-1 pl-4">
				{tabButton('personal', t('billing.tabPersonal'), personalAccounts.length === 0)}
				{tabButton('business', t('billing.tabBusiness'), societyAccounts.length === 0)}
			</div>

			<div className="relative overflow-y-auto bg-[#f7f1e1] text-[#2b2a28] rounded-b-md rounded-tr-md border border-[#b9ad92] shadow-[0_22px_50px_rgba(0,0,0,0.55),0_2px_0_rgba(255,255,255,0.4)_inset] bg-[repeating-linear-gradient(to_bottom,transparent_0,transparent_27px,rgba(150,135,100,0.14)_27px,rgba(150,135,100,0.14)_28px)]">
				{/* perforated tear-off edge */}
				<div className="h-3 border-b-2 border-dotted border-[#b9ad92] bg-[#efe6cd]" aria-hidden="true" />

				<button
					type="button"
					onClick={handleClose}
					aria-label={t('common.close')}
					title={t('common.close')}
					className="absolute top-4 right-3 w-7 h-7 rounded-full flex items-center justify-center text-[#7a705b] hover:text-[#2b2a28] hover:bg-black/5 cursor-pointer border-0 bg-transparent"
				>
					<CloseIcon width={15} height={15} />
				</button>

				<div className="px-6 pt-3 pb-6 flex flex-col gap-4">
					<header className="flex items-baseline justify-between pr-8">
						<h1 className="m-0 font-serif text-[22px] tracking-[0.28em] font-bold text-[#2b2a28]">{t('billing.sheetTitle')}</h1>
						<span className="font-mono text-[13px] text-[#a3382f] tabular-nums">{t('billing.number')} {billNumber}</span>
					</header>

					{isBusiness ? accountSelect(societyAccounts, societyId, setSocietyId) : accountSelect(personalAccounts, personalId, setPersonalId)}

					<section className="flex flex-col gap-1.5">
						<div className="flex items-center justify-between">
							<span className={LABEL}>{t('billing.to')}</span>
							<button
								type="button"
								onClick={loadNearby}
								aria-label={t('billing.refresh')}
								title={t('billing.refresh')}
								className="w-6 h-6 rounded-full flex items-center justify-center text-[#7a705b] hover:text-[#2b2a28] cursor-pointer border-0 bg-transparent"
							>
								<RefreshIcon width={13} height={13} className={refreshing ? 'animate-spin' : ''} />
							</button>
						</div>
						{nearby.length === 0 ? (
							<p className="m-0 text-[12px] italic text-[#7a705b]">{t('billing.nearbyEmpty')}</p>
						) : (
							<div className="flex flex-col max-h-[112px] overflow-y-auto">
								{nearby.map((player) => {
									const selected = recipient.trim() === String(player.id);

									return (
										<button
											key={player.id}
											type="button"
											onClick={() => setRecipient(String(player.id))}
											className={`text-left px-2 py-1 text-[13px] border-0 border-b border-dashed border-[#c9bea3] cursor-pointer transition-colors ${selected ? 'bg-[#1f3a6e]/10 text-[#1f3a6e] font-semibold' : 'bg-transparent text-[#2b2a28] hover:bg-black/5'}`}
										>
											{t('billing.nearbyId', { name: player.name, id: player.id })}
										</button>
									);
								})}
							</div>
						)}
						<input
							className={LINE_INPUT}
							type="text"
							placeholder={t('billing.recipientPlaceholder')}
							value={recipient}
							onChange={(e) => setRecipient(e.target.value)}
							disabled={busy}
						/>
					</section>

					<label className="flex flex-col gap-0.5">
						<span className={LABEL}>{t('billing.for')}</span>
						<input
							className={LINE_INPUT}
							type="text"
							maxLength={255}
							placeholder={t('billing.forPlaceholder')}
							value={reason}
							onChange={(e) => setReason(e.target.value)}
							disabled={busy}
						/>
					</label>

					<label className="flex flex-col gap-0.5">
						<span className={LABEL}>{t('billing.amount')}</span>
						<div className="flex items-baseline gap-1">
							<span className={`${INK} text-[16px] font-semibold`}>{currencySymbol}</span>
							<input
								className={`${LINE_INPUT} text-[18px] tabular-nums`}
								type="text"
								inputMode="numeric"
								placeholder="0"
								value={amount}
								onChange={(e) => setAmount(e.target.value.replace(/\D/g, '').slice(0, 9))}
								disabled={busy}
							/>
						</div>
					</label>

					{isBusiness ? (
						<section className="flex flex-col gap-1.5">
							<span className={LABEL}>{t('billing.split')}</span>
							<div className="flex items-center gap-3">
								<input
									type="range"
									min={0}
									max={maxShare}
									step={1}
									value={Math.min(share, maxShare)}
									onChange={(e) => setShare(Number(e.target.value))}
									disabled={busy || maxShare === 0}
									className="flex-1 accent-[#1f3a6e] cursor-pointer"
								/>
								<span className={`${INK} font-semibold text-[13px] tabular-nums w-10 text-right`}>{Math.min(share, maxShare)}%</span>
							</div>
							<div className="flex justify-between text-[12px] text-[#5b523f]">
								<span>{t('billing.youGet', { percent: Math.min(share, maxShare) })}</span>
								<span>{t('billing.businessGets', { percent: 100 - Math.min(share, maxShare) })}</span>
							</div>
							<p className={`m-0 text-[13px] font-medium ${INK} tabular-nums`}>
								{t('billing.splitMoney', { you: formatMoney(youGet, currencySymbol), business: formatMoney(businessGets, currencySymbol) })}
							</p>
						</section>
					) : (
						<p className="m-0 text-[12px] italic text-[#5b523f]">{t('billing.toOwnAccount')}</p>
					)}

					<div className="flex items-center justify-between gap-3 min-h-[56px]">
						<div className="text-[12px]">
							{error && <p className="m-0 text-[#a3382f] font-medium">{error}</p>}
							{sent && !error && <p className="m-0 text-[#2f6b3c] font-semibold">{t('billing.sent')}</p>}
						</div>
						<button
							type="button"
							onClick={send}
							disabled={!canSend}
							className="shrink-0 rotate-[-4deg] px-5 py-2 rounded-md border-[3px] border-double border-[#a3382f] text-[#a3382f] bg-transparent font-serif font-bold text-[15px] tracking-[0.25em] cursor-pointer transition-all hover:bg-[#a3382f]/10 active:scale-95 disabled:opacity-35 disabled:cursor-not-allowed"
						>
							{t('billing.send')}
						</button>
					</div>
				</div>
			</div>
		</motion.div>
	);
}
