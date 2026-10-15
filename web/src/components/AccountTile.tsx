import { useState } from 'react';
import type { MouseEvent } from 'react';
import type { TbAccount } from '../types';
import { useTranslation } from '../i18n/context';
import { formatMoney } from '../format';
import { useSavingsLock } from '../hooks/useSavingsLock';
import { CopyIcon, CheckIcon, LockIcon, StarIcon } from '../icons';
import { NumberTicker } from './ui/NumberTicker';
import { Tooltip } from './ui/Tooltip';

interface AccountTileProps {
	account: TbAccount;
	currencySymbol: string;
	selected?: boolean;
	onSelect?: (account: TbAccount) => void;
}

/** One color mark per account type, the only decoration on the tile, so a row of them still reads as one calm group. */
const TYPE_DOT: Record<TbAccount['type'], string> = {
	personal: 'bg-[var(--tb-accent)]',
	savings: 'bg-[var(--tb-success)]',
	society: 'bg-[var(--tb-text-muted)]',
};

/** The pefcl-style account tile: name, type, number with copy, balance. The default account carries the ESX-bank marker. */
export function AccountTile({ account, currencySymbol, selected = false, onSelect }: AccountTileProps) {
	const { t } = useTranslation();
	const [copied, setCopied] = useState(false);
	const lock = useSavingsLock(account);

	function copy(event: MouseEvent) {
		event.stopPropagation();

		try {
			navigator.clipboard?.writeText(account.number);
		} catch {
			// Clipboard can be unavailable inside the NUI runtime, the number is visible anyway.
		}

		setCopied(true);
		setTimeout(() => setCopied(false), 1200);
	}

	return (
		<div
			role={onSelect ? 'button' : undefined}
			onClick={() => onSelect?.(account)}
			className={`bg-[var(--tb-surface)] rounded-xl px-5 py-4 flex flex-col gap-4 transition-shadow ${
				selected ? 'shadow-[inset_0_0_0_1.5px_var(--tb-accent)]' : ''
			} ${onSelect ? 'cursor-pointer hover:shadow-[inset_0_0_0_1px_var(--tb-text-muted)]' : ''}`}
		>
			<div className="flex items-center gap-2 min-w-0">
				<span className={`w-2 h-2 rounded-full shrink-0 ${TYPE_DOT[account.type]}`} />
				<span className="text-[13px] font-medium truncate">{account.name}</span>
				{account.isDefault && (
					<Tooltip content={t('account.esxLinkedHint')} className="inline-flex shrink-0">
						<StarIcon width={12} height={12} className="text-[var(--tb-accent)] cursor-default" aria-label={t('account.esxLinked')} />
					</Tooltip>
				)}
				<span className="ml-auto text-[11px] text-[var(--tb-text-muted)] whitespace-nowrap">
					{account.type === 'savings' && account.interestRate !== null ? t('account.interest', { rate: account.interestRate }) : t(`account.${account.type}`)}
				</span>
			</div>

			<NumberTicker value={account.balance} format={(value) => formatMoney(value, currencySymbol)} className="text-[22px] font-semibold tabular-nums tracking-tight leading-none" />

			<div className="flex items-center gap-1.5 text-xs tabular-nums text-[var(--tb-text-muted)]">
				<span>{account.number}</span>
				<Tooltip content={copied ? t('common.copied') : t('account.copyHint')}>
					<button type="button" className="inline-flex text-[var(--tb-text-muted)] hover:text-[var(--tb-text-primary)] cursor-pointer" onClick={copy} aria-label={t('common.copy')}>
						{copied ? <CheckIcon width={12} height={12} /> : <CopyIcon width={12} height={12} />}
					</button>
				</Tooltip>
				{account.type === 'savings' && (
					<Tooltip content={lock.locked ? `${lock.text}. ${t('account.lockHint')}` : t('account.lockHint')} className="ml-auto inline-flex">
						<span className={`inline-flex items-center gap-1 ${lock.locked ? 'text-[var(--tb-warning)]' : 'text-[var(--tb-success)]'}`}>
							{lock.locked ? <LockIcon width={11} height={11} /> : <CheckIcon width={11} height={11} />} {lock.short}
						</span>
					</Tooltip>
				)}
			</div>
		</div>
	);
}
