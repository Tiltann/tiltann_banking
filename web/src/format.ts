/**
 * Dates reach the NUI in whichever shape the server's MySQL layer produced.
 * oxmysql hands DATETIME/DATE columns over as epoch MILLISECONDS by default,
 * and as the raw "YYYY-MM-DD HH:MM:SS" string on servers that set
 * `mysql_string_dates`. Neither is something this resource controls, so
 * every formatter here accepts both, passing a number to String.replace is
 * what crashed the whole UI with "e.replace is not a function".
 */
export type SqlDateTime = string | number | null | undefined;

/** Parses either shape into a Date, or null when the value is absent or unparseable. */
function toDate(value: SqlDateTime): Date | null {
	if (value === null || value === undefined || value === '') {
		return null;
	}

	if (typeof value === 'number') {
		const fromEpoch = new Date(value);
		return Number.isNaN(fromEpoch.getTime()) ? null : fromEpoch;
	}

	// MySQL's "YYYY-MM-DD HH:MM:SS" is not valid ISO 8601: it needs the T
	// separator, and it carries no zone even though the server stores UTC.
	const normalized = value.includes('T') ? value : value.replace(' ', 'T');
	const withZone = /[Zz]|[+-]\d{2}:?\d{2}$/.test(normalized) ? normalized : `${normalized}Z`;
	const parsed = new Date(withZone);

	return Number.isNaN(parsed.getTime()) ? null : parsed;
}

/** Shown wherever a date is missing or unparseable, so a bad value is visible instead of crashing the page. */
const NO_DATE = '-';

export function formatMoney(amount: number, currencySymbol: string): string {
	return `${currencySymbol}${(Number(amount) || 0).toLocaleString('en-US')}`;
}

/** Adds the year only when the date is not in the current year, so recent dates stay short. */
function yearOption(date: Date): { year?: 'numeric' } {
	return date.getUTCFullYear() === new Date().getUTCFullYear() ? {} : { year: 'numeric' };
}

/** A single day from a grouped query (the week and cash-flow charts). */
export function formatDay(isoDay: SqlDateTime, locale = 'en'): string {
	const date = typeof isoDay === 'string' && !isoDay.includes(':') ? toDate(`${isoDay} 00:00:00`) : toDate(isoDay);
	return date ? date.toLocaleDateString(locale, { month: 'short', day: 'numeric', ...yearOption(date), timeZone: 'UTC' }) : NO_DATE;
}

export function formatDate(sqlDateTime: SqlDateTime, locale = 'en'): string {
	const date = toDate(sqlDateTime);
	return date ? date.toLocaleDateString(locale, { month: 'short', day: 'numeric', ...yearOption(date), timeZone: 'UTC' }) : NO_DATE;
}

/** Milliseconds from now until a SQL datetime, 0 when it is missing or already past. */
export function msUntil(sqlDateTime: SqlDateTime): number {
	const date = toDate(sqlDateTime);
	return date ? Math.max(0, date.getTime() - Date.now()) : 0;
}

/** True while a SQL datetime lies in the future (savings lock, invoice due). */
export function isFuture(sqlDateTime: SqlDateTime): boolean {
	const date = toDate(sqlDateTime);
	return date !== null && date.getTime() > Date.now();
}

export function formatTimestamp(sqlDateTime: SqlDateTime, locale = 'en'): string {
	const date = toDate(sqlDateTime);

	if (!date) {
		return NO_DATE;
	}

	return date.toLocaleString(locale, {
		month: 'short',
		day: 'numeric',
		...yearOption(date),
		hour: '2-digit',
		minute: '2-digit',
		timeZone: 'UTC',
	});
}
