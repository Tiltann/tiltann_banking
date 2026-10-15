import type { TranslateFn } from './i18n/context';

const MINUTE = 60;
const HOUR = 3600;
const DAY = 86400;

/** Picks the largest unit that fits and rounds to a whole number of it (at least 1). */
function pickUnit(seconds: number): { unit: 'day' | 'hour' | 'minute'; n: number } {
	if (seconds >= DAY) {
		return { unit: 'day', n: Math.max(1, Math.round(seconds / DAY)) };
	}

	if (seconds >= HOUR) {
		return { unit: 'hour', n: Math.max(1, Math.round(seconds / HOUR)) };
	}

	return { unit: 'minute', n: Math.max(1, Math.round(seconds / MINUTE)) };
}

/** "1 day", "7 days", "6 hours". */
export function durationLabel(seconds: number, t: TranslateFn): string {
	const { unit, n } = pickUnit(seconds);
	return t(n === 1 ? `time.${unit}` : `time.${unit}s`, { n });
}

/** "every day", "every 2 days", "every 6 hours". */
export function intervalLabel(seconds: number, t: TranslateFn): string {
	const { unit, n } = pickUnit(seconds);
	return t(n === 1 ? `time.every.${unit}` : `time.every.${unit}s`, { n });
}

/** Compact remaining time: "6d 4h 12m", "4h 12m", "12m". Rounds up to a full minute. */
export function remainingLabel(ms: number, t: TranslateFn): string {
	const totalMinutes = Math.max(1, Math.ceil(ms / 60000));
	const days = Math.floor(totalMinutes / 1440);
	const hours = Math.floor((totalMinutes % 1440) / 60);
	const minutes = totalMinutes % 60;
	const parts: string[] = [];

	if (days > 0) {
		parts.push(t('time.short.d', { n: days }));
	}

	if (days > 0 || hours > 0) {
		parts.push(t('time.short.h', { n: hours }));
	}

	parts.push(t('time.short.m', { n: minutes }));

	return parts.join(' ');
}
