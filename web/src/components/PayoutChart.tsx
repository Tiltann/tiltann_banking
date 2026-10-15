import { Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import type { TbDailyTotals, TbUiColors } from '../types';
import { formatDay, formatMoney } from '../format';
import { useTranslation } from '../i18n/context';

interface PayoutChartProps {
	days: TbDailyTotals[];
	colors: TbUiColors;
	currencySymbol: string;
}

interface TooltipPayloadEntry {
	dataKey: string;
	value: number;
	color: string;
}

function ChartTooltip({
	active,
	payload,
	label,
	currencySymbol,
}: {
	active?: boolean;
	payload?: TooltipPayloadEntry[];
	label?: string;
	currencySymbol: string;
}) {
	const { t, lang } = useTranslation();

	if (!active || !payload || payload.length === 0) {
		return null;
	}

	const names: Record<string, string> = {
		deposits: t('chart.deposits'),
		withdrawals: t('chart.withdrawals'),
		adminAdjustments: t('chart.adminAdjustments'),
	};

	return (
		<div className="bg-[var(--tb-primary)] border border-[var(--tb-secondary)] rounded-lg px-3 py-2.5 text-xs">
			<span className="block text-[var(--tb-text-muted)] mb-1.5">{label ? formatDay(label, lang) : ''}</span>
			{payload.map((entry) => (
				<div className="flex items-center gap-1.5 py-0.5" key={entry.dataKey}>
					<span className="w-2 h-2 rounded-sm shrink-0" style={{ background: entry.color }} />
					<span className="text-[var(--tb-text-primary)]">{names[entry.dataKey] ?? entry.dataKey}</span>
					<span className="ml-auto tabular-nums">{formatMoney(entry.value, currencySymbol)}</span>
				</div>
			))}
		</div>
	);
}

/**
 * Area chart of the society account's grouped daily totals, the "money
 * given out" view the client asked for, including admin_adjustment rows so
 * a SetAccountMoney-style reset shows up honestly instead of vanishing.
 */
export function PayoutChart({ days, colors, currencySymbol }: PayoutChartProps) {
	const { t, lang } = useTranslation();

	if (days.length === 0) {
		return <div className="text-[var(--tb-text-muted)] text-[13px] py-6 text-center">{t('chart.empty')}</div>;
	}

	return (
		<ResponsiveContainer width="100%" height={220}>
			<AreaChart data={days} margin={{ top: 8, right: 12, left: 0, bottom: 0 }}>
				<defs>
					<linearGradient id="fillDeposits" x1="0" y1="0" x2="0" y2="1">
						<stop offset="5%" stopColor={colors.success} stopOpacity={0.35} />
						<stop offset="95%" stopColor={colors.success} stopOpacity={0} />
					</linearGradient>
					<linearGradient id="fillWithdrawals" x1="0" y1="0" x2="0" y2="1">
						<stop offset="5%" stopColor={colors.danger} stopOpacity={0.35} />
						<stop offset="95%" stopColor={colors.danger} stopOpacity={0} />
					</linearGradient>
					<linearGradient id="fillAdmin" x1="0" y1="0" x2="0" y2="1">
						<stop offset="5%" stopColor={colors.warning} stopOpacity={0.35} />
						<stop offset="95%" stopColor={colors.warning} stopOpacity={0} />
					</linearGradient>
				</defs>
				<CartesianGrid stroke={colors.secondary} strokeDasharray="3 3" vertical={false} />
				<XAxis
					dataKey="day"
					tickFormatter={(day: string) => formatDay(day, lang)}
					stroke={colors.textMuted}
					tick={{ fill: colors.textMuted, fontSize: 12 }}
					axisLine={{ stroke: colors.secondary }}
					tickLine={false}
				/>
				<YAxis
					stroke={colors.textMuted}
					tick={{ fill: colors.textMuted, fontSize: 12 }}
					axisLine={false}
					tickLine={false}
					width={48}
					tickFormatter={(value: number) => `${currencySymbol}${Math.round(value / 1000)}k`}
				/>
				<Tooltip content={<ChartTooltip currencySymbol={currencySymbol} />} />
				<Area
					type="monotone"
					dataKey="deposits"
					stroke={colors.success}
					fill="url(#fillDeposits)"
					strokeWidth={2}
				/>
				<Area
					type="monotone"
					dataKey="withdrawals"
					stroke={colors.danger}
					fill="url(#fillWithdrawals)"
					strokeWidth={2}
				/>
				<Area
					type="monotone"
					dataKey="adminAdjustments"
					stroke={colors.warning}
					fill="url(#fillAdmin)"
					strokeWidth={2}
				/>
			</AreaChart>
		</ResponsiveContainer>
	);
}
