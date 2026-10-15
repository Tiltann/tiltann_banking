import { useEffect, useState } from 'react';
import type { TbTransaction, TbTransactionFilters } from '../types';
import { fetchNui } from '../api/nui';
import { useTranslation } from '../i18n/context';
import { formatMoney, formatTimestamp } from '../format';
import { BTN_GHOST } from '../ui-classes';
import { translateNote } from '../txNotes';

interface TransactionTableProps {
	accountId: number;
	currencySymbol: string;
	filters?: TbTransactionFilters;
	/** Seed rows (e.g. the dashboard's latest list), pass with `compact` to render without pagination. */
	initialTransactions?: TbTransaction[];
	compact?: boolean;
}

const PAGE_SIZE = 25;

/** Paginated, filterable statement for one account. Fetches page 0 itself on mount and again whenever `filters` change. */
export function TransactionTable({ accountId, currencySymbol, filters, initialTransactions, compact = false }: TransactionTableProps) {
	const { t, lang } = useTranslation();
	const [transactions, setTransactions] = useState<TbTransaction[]>(initialTransactions ?? []);
	const [loading, setLoading] = useState(false);
	const [exhausted, setExhausted] = useState(compact);

	async function load(offset: number, replace: boolean) {
		setLoading(true);

		try {
			const page = await fetchNui<TbTransaction[]>('tiltann_banking:ui:transactions', { accountId, offset, filters });
			setTransactions((current) => (replace ? page : [...current, ...page]));
			setExhausted(page.length < PAGE_SIZE);
		} finally {
			setLoading(false);
		}
	}

	useEffect(() => {
		if (!compact) {
			load(0, true);
		}
	}, [accountId, JSON.stringify(filters ?? {})]);

	const rowGrid = 'grid [grid-template-columns:130px_150px_1fr_120px] gap-3 items-center';

	return (
		<div className="flex flex-col">
			<div className={`${rowGrid} text-[11px] uppercase tracking-wide text-[var(--tb-text-muted)] px-1 pb-2.5 border-b border-[var(--tb-secondary)]`}>
				<span>{t('tx.date')}</span>
				<span>{t('tx.type')}</span>
				<span>{t('tx.note')}</span>
				<span className="text-right">{t('tx.amount')}</span>
			</div>

			{transactions.length === 0 && !loading && (
				<p className="text-[var(--tb-text-muted)] text-[13px] text-center py-5 m-0">{t('tx.empty')}</p>
			)}

			<div className="flex flex-col">
				{transactions.map((tx) => {
					// old sync corrections were stored with a negative amount on the receiving side
					const isCredit = tx.toAccountId === accountId && tx.amount >= 0;

					return (
						<div className={`${rowGrid} py-2.5 px-1 text-[13px] border-b border-[var(--tb-secondary)]/60 last:border-b-0`} key={tx.id}>
							<span className="text-[var(--tb-text-muted)]">{formatTimestamp(tx.createdAt, lang)}</span>
							<span>{t(`tx.type.${tx.type}`)}</span>
							<span className="text-[var(--tb-text-muted)] truncate">{translateNote(tx.note, t) ?? '-'}</span>
							<span className={`text-right tabular-nums ${isCredit ? 'text-[var(--tb-success)]' : 'text-[var(--tb-danger)]'}`}>
								{isCredit ? '+' : '-'}
								{formatMoney(Math.abs(tx.amount), currencySymbol)}
							</span>
						</div>
					);
				})}
			</div>

			{!exhausted && (
				<button
					className={`${BTN_GHOST} self-center mt-3.5`}
					onClick={() => load(transactions.length, false)}
					disabled={loading}
				>
					{loading ? t('tx.loading') : t('tx.loadMore')}
				</button>
			)}
		</div>
	);
}
