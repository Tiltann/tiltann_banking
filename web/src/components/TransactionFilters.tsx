import { useState } from 'react';
import type { TbTransactionFilters, TbTransactionType } from '../types';
import { useTranslation } from '../i18n/context';
import { FilterIcon } from '../icons';
import { BTN_GHOST, BTN_PRIMARY, FIELD_LABEL, INPUT, SELECT } from '../ui-classes';

const TYPES: TbTransactionType[] = [
	'deposit', 'withdraw', 'transfer', 'tax', 'interest', 'standing_order',
	'loan_disbursement', 'loan_repayment', 'invoice_payment', 'account_fee',
	'admin_adjustment', 'sync_correction',
];

interface TransactionFiltersProps {
	onChange: (filters: TbTransactionFilters | undefined) => void;
}

/** Type / amount range / date range filters for the statement view. Applied on demand, not per keystroke, so each apply is one fetch. */
export function TransactionFilters({ onChange }: TransactionFiltersProps) {
	const { t } = useTranslation();
	const [type, setType] = useState('');
	const [minAmount, setMinAmount] = useState('');
	const [maxAmount, setMaxAmount] = useState('');
	const [from, setFrom] = useState('');
	const [to, setTo] = useState('');

	function apply() {
		const filters: TbTransactionFilters = {};

		if (type) filters.type = type as TbTransactionType;
		if (minAmount) filters.minAmount = Number(minAmount);
		if (maxAmount) filters.maxAmount = Number(maxAmount);
		if (from) filters.from = from;
		if (to) filters.to = to;

		onChange(Object.keys(filters).length > 0 ? filters : undefined);
	}

	function clear() {
		setType('');
		setMinAmount('');
		setMaxAmount('');
		setFrom('');
		setTo('');
		onChange(undefined);
	}

	return (
		<div className="flex flex-wrap items-end gap-2">
			<label className={FIELD_LABEL}>
				{t('tx.filter.type')}
				<select className={SELECT} value={type} onChange={(e) => setType(e.target.value)}>
					<option value="">{t('tx.filter.any')}</option>
					{TYPES.map((value) => (
						<option key={value} value={value}>{t(`tx.type.${value}`)}</option>
					))}
				</select>
			</label>
			<label className={`${FIELD_LABEL} w-24`}>
				{t('tx.filter.min')}
				<input className={INPUT} type="number" min={0} value={minAmount} onChange={(e) => setMinAmount(e.target.value)} />
			</label>
			<label className={`${FIELD_LABEL} w-24`}>
				{t('tx.filter.max')}
				<input className={INPUT} type="number" min={0} value={maxAmount} onChange={(e) => setMaxAmount(e.target.value)} />
			</label>
			<label className={FIELD_LABEL}>
				{t('tx.filter.from')}
				<input className={INPUT} type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
			</label>
			<label className={FIELD_LABEL}>
				{t('tx.filter.to')}
				<input className={INPUT} type="date" value={to} onChange={(e) => setTo(e.target.value)} />
			</label>
			<button type="button" className={BTN_PRIMARY} onClick={apply}>
				<FilterIcon width={14} height={14} /> {t('tx.filter.apply')}
			</button>
			<button type="button" className={BTN_GHOST} onClick={clear}>
				{t('tx.filter.clear')}
			</button>
		</div>
	);
}
