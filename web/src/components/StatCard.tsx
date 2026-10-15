import type { ReactNode } from 'react';
import { NumberTicker } from './ui/NumberTicker';

interface StatCardProps {
	label: string;
	value: number;
	format: (value: number) => string;
	tone?: 'default' | 'success' | 'danger';
	/** Optional trailing element next to the label, e.g. a tooltip trigger. */
	hint?: ReactNode;
}

const TONE_CLASSES: Record<NonNullable<StatCardProps['tone']>, string> = {
	default: '',
	success: 'text-[var(--tb-success)]',
	danger: 'text-[var(--tb-danger)]',
};

/** One tile in a stat row, the figure ticks to its value instead of snapping. */
export function StatCard({ label, value, format, tone = 'default', hint }: StatCardProps) {
	return (
		<div className="bg-[var(--tb-surface)] rounded-xl px-5 py-4 flex flex-col gap-1.5 min-w-[180px]">
			<span className="flex items-center gap-1.5 text-[11px] uppercase tracking-[0.08em] text-[var(--tb-text-muted)]">
				{label} {hint}
			</span>
			<NumberTicker value={value} format={format} className={`text-[22px] font-semibold tabular-nums tracking-tight ${TONE_CLASSES[tone]}`} />
		</div>
	);
}
