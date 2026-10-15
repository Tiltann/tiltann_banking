import type { TbTransaction } from '../types';
import { useTranslation } from '../i18n/context';
import { formatMoney, formatTimestamp } from '../format';
import { NOTE } from '../ui-classes';
import { translateNote } from '../txNotes';

interface TxListProps {
	transactions: TbTransaction[];
	/** Accounts the viewer owns, decides whether a row is money in, money out, or a move between own accounts. */
	ownedIds: Set<number>;
	currencySymbol: string;
}

/** Compact "latest transactions" list shared by the dashboards and the ATM. Not paginated, see TransactionTable for that. */
export function TxList({ transactions, ownedIds, currencySymbol }: TxListProps) {
	const { t, lang } = useTranslation();

	if (transactions.length === 0) {
		return <p className={NOTE}>{t('tx.empty')}</p>;
	}

	return (
		<div className="flex flex-col">
			{transactions.map((tx) => {
				const fromOwn = tx.fromAccountId !== null && ownedIds.has(tx.fromAccountId);
				const toOwn = tx.toAccountId !== null && ownedIds.has(tx.toAccountId);
				const isInternal = fromOwn && toOwn;
				const isCredit = toOwn && !fromOwn && tx.amount >= 0;
				const note = translateNote(tx.note, t);

				return (
					<div key={tx.id} className="grid [grid-template-columns:1fr_auto] gap-x-4 gap-y-0.5 py-2.5 border-b border-[var(--tb-secondary)]/60 last:border-b-0">
						<span className="text-[13px] truncate">{t(`tx.type.${tx.type}`)}{note ? ` · ${note}` : ''}</span>
						<span className={`text-[13px] tabular-nums text-right ${isInternal ? 'text-[var(--tb-text-muted)]' : isCredit ? 'text-[var(--tb-success)]' : 'text-[var(--tb-text-primary)]'}`}>
							{isInternal ? '' : isCredit ? '+' : '-'}{formatMoney(Math.abs(tx.amount), currencySymbol)}
						</span>
						<span className="text-[11px] text-[var(--tb-text-muted)] tabular-nums">{formatTimestamp(tx.createdAt, lang)}</span>
					</div>
				);
			})}
		</div>
	);
}
