import { useEffect, useState } from 'react';
import type { TbTaxOverview } from '../types';
import { fetchNui } from '../api/nui';
import { useTranslation } from '../i18n/context';
import { formatMoney, formatTimestamp } from '../format';
import { BADGE, NOTE, PANEL, PANEL_TITLE } from '../ui-classes';
import { StatCard } from './StatCard';
import { BlurFade } from './ui/BlurFade';

interface TaxPanelProps {
	currencySymbol: string;
}

/**
 * The Personal tab's Tax page: what the player has paid (all time / this
 * month), the rules in force (rate or brackets, which operations, where the
 * money goes) and their recent tax records, all straight from
 * Config.Tax via server/tax/tax.lua.
 */
export function TaxPanel({ currencySymbol }: TaxPanelProps) {
	const { t, lang } = useTranslation();
	const [overview, setOverview] = useState<TbTaxOverview | null>(null);
	const money = (value: number) => formatMoney(value, currencySymbol);

	useEffect(() => {
		fetchNui<TbTaxOverview>('tiltann_banking:ui:tax:get').then(setOverview);
	}, []);

	if (!overview) {
		return <p className={NOTE}>{t('common.loading')}</p>;
	}

	if (!overview.enabled) {
		return <p className={NOTE}>{t('tax.disabled')}</p>;
	}

	const records = overview.records ?? [];
	const appliesOn = overview.appliesOn ?? [];
	const destination =
		overview.destinationType === 'burn' ? t('tax.destinationBurn') : (overview.destinationName ?? t('tax.destinationUnknown'));

	return (
		<>
			<BlurFade>
				<div className="grid [grid-template-columns:repeat(auto-fit,minmax(200px,1fr))] gap-3">
					<StatCard label={t('tax.paidTotal')} value={overview.totalPaid ?? 0} format={money} />
					<StatCard label={t('tax.paidPeriod', { days: overview.periodDays ?? 30 })} value={overview.paidInPeriod ?? 0} format={money} />
				</div>
			</BlurFade>

			<BlurFade delay={0.08}>
				<section className={PANEL}>
					<h2 className={PANEL_TITLE}>{t('tax.rules')}</h2>
					<div className="grid [grid-template-columns:repeat(auto-fit,minmax(220px,1fr))] gap-x-6 gap-y-3 text-[13px]">
						<div className="flex flex-col gap-1">
							<span className="text-[11px] uppercase tracking-[0.08em] text-[var(--tb-text-muted)]">{t('tax.rate')}</span>
							{overview.mode === 'bracket' ? (
								<div className="flex flex-col">
									{(overview.brackets ?? []).map((bracket) => (
										<span key={bracket.min} className="tabular-nums flex justify-between gap-3 py-0.5">
											<span className="text-[var(--tb-text-muted)]">
												{money(bracket.min)}{bracket.max === null ? '+' : ` to ${money(bracket.max)}`}
											</span>
											<span>{bracket.rate}%</span>
										</span>
									))}
								</div>
							) : (
								<span className="tabular-nums">{overview.flatRate ?? 0}%</span>
							)}
							{(overview.minTaxableAmount ?? 0) > 0 && (
								<span className="text-[var(--tb-text-muted)] text-xs">{t('tax.minAmount', { amount: money(overview.minTaxableAmount ?? 0) })}</span>
							)}
						</div>

						<div className="flex flex-col gap-1">
							<span className="text-[11px] uppercase tracking-[0.08em] text-[var(--tb-text-muted)]">{t('tax.appliesOn')}</span>
							<div className="flex flex-wrap gap-1.5">
								{appliesOn.length === 0 && !overview.periodic && <span className={NOTE}>{t('tax.appliesNone')}</span>}
								{appliesOn.map((kind) => (
									<span key={kind} className={BADGE.neutral}>{t(`tax.kind.${kind}`)}</span>
								))}
								{overview.periodic && (
									<span className={BADGE.neutral}>
										{t('tax.kind.periodic')} · {overview.periodic.rate}% / {Math.round(overview.periodic.intervalSeconds / 3600)}h
									</span>
								)}
							</div>
						</div>

						<div className="flex flex-col gap-1">
							<span className="text-[11px] uppercase tracking-[0.08em] text-[var(--tb-text-muted)]">{t('tax.destination')}</span>
							<span>{destination}</span>
						</div>
					</div>
				</section>
			</BlurFade>

			<BlurFade delay={0.14}>
				<section className={PANEL}>
					<h2 className={PANEL_TITLE}>{t('tax.history')}</h2>
					{records.length === 0 && <p className={NOTE}>{t('tax.none')}</p>}
					{records.length > 0 && (
						<div className="flex flex-col">
							<div className="grid [grid-template-columns:130px_1fr_110px_70px_110px] gap-3 text-[11px] uppercase tracking-wide text-[var(--tb-text-muted)] px-1 pb-2.5 border-b border-[var(--tb-secondary)]/60">
								<span>{t('tx.date')}</span>
								<span>{t('tx.type')}</span>
								<span className="text-right">{t('tax.taxable')}</span>
								<span className="text-right">{t('tax.rate')}</span>
								<span className="text-right">{t('tax.tax')}</span>
							</div>
							{records.map((record) => (
								<div key={record.id} className="grid [grid-template-columns:130px_1fr_110px_70px_110px] gap-3 items-center py-2.5 px-1 text-[13px] border-b border-[var(--tb-secondary)]/60 last:border-b-0">
									<span className="text-[var(--tb-text-muted)] tabular-nums">{formatTimestamp(record.createdAt, lang)}</span>
									<span className="truncate">{t(`tax.kind.${record.kind}`)} · <span className="text-[var(--tb-text-muted)]">{record.accountName}</span></span>
									<span className="text-right tabular-nums text-[var(--tb-text-muted)]">{money(record.taxableAmount)}</span>
									<span className="text-right tabular-nums text-[var(--tb-text-muted)]">{record.rate}%</span>
									<span className="text-right tabular-nums text-[var(--tb-danger)]">-{money(record.taxAmount)}</span>
								</div>
							))}
						</div>
					)}
				</section>
			</BlurFade>
		</>
	);
}
