import { useTranslation } from '../i18n/context';
import { useNow } from './useNow';
import { formatTimestamp, isFuture, msUntil } from '../format';
import { remainingLabel } from '../duration';
import type { TbAccount } from '../types';

/** Live savings-lock text: remaining time plus the unlock moment, or "Available now". Updates every 30s. */
export function useSavingsLock(account: Pick<TbAccount, 'type' | 'lockedUntil'>): { locked: boolean; text: string; short: string } {
	const { t, lang } = useTranslation();
	useNow(30000);

	const locked = account.type === 'savings' && isFuture(account.lockedUntil);

	if (!locked) {
		return { locked: false, text: t('account.unlocked'), short: t('account.unlocked') };
	}

	const remaining = remainingLabel(msUntil(account.lockedUntil), t);

	return {
		locked: true,
		text: t('account.unlocksIn', { remaining, date: formatTimestamp(account.lockedUntil, lang) }),
		short: remaining,
	};
}
