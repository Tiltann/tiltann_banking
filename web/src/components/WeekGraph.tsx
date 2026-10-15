import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import type { TbUiColors, TbWeekPoint } from '../types';
import { formatDay, formatMoney } from '../format';
import { useTranslation } from '../i18n/context';

interface WeekGraphProps {
	points: TbWeekPoint[];
	colors: TbUiColors;
	currencySymbol: string;
}

interface TooltipEntry {
	dataKey: string;
	value: number;
	color: string;
}

function WeekTooltip({ active, payload, label, currencySymbol }: { active?: boolean; payload?: TooltipEntry[]; label?: string; currencySymbol: string }) {
	const { t, lang } = useTranslation();

	if (!active || !payload || payload.length === 0) {
		return null;
	}

	return (
		<div className="bg-[var(--tb-primary)] border border-[var(--tb-secondary)] rounded-lg px-3 py-2.5 text-xs">
			<span className="block text-[var(--tb-text-muted)] mb-1.5">{label ? formatDay(label, lang) : ''}</span>
			{payload.map((entry) => (
				<div className="flex items-center gap-1.5 py-0.5" key={entry.dataKey}>
					<span className="w-2 h-2 rounded-sm shrink-0" style={{ background: entry.color }} />
					<span>{t(entry.dataKey === 'income' ? 'chart.income' : 'chart.expenses')}</span>
					<span className="ml-auto tabular-nums">{formatMoney(entry.value, currencySymbol)}</span>
				</div>
			))}
		</div>
	);
}

/** Income vs expenses across all of a player's accounts, last 7 days (the pefcl "Summary"). */
export function WeekGraph({ points, colors, currencySymbol }: WeekGraphProps) {
	const { t, lang } = useTranslation();

	if (points.length === 0) {
		return <div className="text-[var(--tb-text-muted)] text-[13px] py-6 text-center">{t('chart.empty')}</div>;
	}

	return (
		<ResponsiveContainer width="100%" height={180}>
			<BarChart data={points} margin={{ top: 8, right: 8, left: 0, bottom: 0 }} barGap={3}>
				<CartesianGrid stroke={colors.secondary} strokeDasharray="3 3" vertical={false} />
				<XAxis dataKey="day" tickFormatter={(day: string) => formatDay(day, lang)} tick={{ fill: colors.textMuted, fontSize: 12 }} axisLine={{ stroke: colors.secondary }} tickLine={false} />
				<YAxis
					tick={{ fill: colors.textMuted, fontSize: 12 }}
					axisLine={false}
					tickLine={false}
					width={56}
					tickFormatter={(value: number) => (value >= 10000 ? `${currencySymbol}${Math.round(value / 1000)}k` : formatMoney(value, currencySymbol))}
				/>
				<Tooltip cursor={{ fill: 'transparent' }} content={<WeekTooltip currencySymbol={currencySymbol} />} />
				<Bar dataKey="income" fill={colors.success} radius={[4, 4, 0, 0]} />
				<Bar dataKey="expenses" fill={colors.danger} radius={[4, 4, 0, 0]} />
			</BarChart>
		</ResponsiveContainer>
	);
}
