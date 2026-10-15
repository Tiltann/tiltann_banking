import { useState } from 'react';
import type { ActionResult } from '../types';
import { fetchNui } from '../api/nui';
import { describeError } from '../errorMessages';
import { useTranslation } from '../i18n/context';
import { TrashIcon } from '../icons';
import { BTN_DANGER, BTN_GHOST, FORM_ERROR } from '../ui-classes';

interface ClearHistoryButtonProps {
	endpoint: string;
	accountId: number;
	onCleared: () => void;
}

/** "Clear history" with an inline two step confirm. Only hides the caller's statement server side, nothing is deleted. */
export function ClearHistoryButton({ endpoint, accountId, onCleared }: ClearHistoryButtonProps) {
	const { t } = useTranslation();
	const [confirming, setConfirming] = useState(false);
	const [busy, setBusy] = useState(false);
	const [error, setError] = useState<string | undefined>(undefined);

	async function clear() {
		setBusy(true);
		setError(undefined);

		const result = await fetchNui<ActionResult>(endpoint, { accountId });

		setBusy(false);

		if (!result.ok) {
			setError(describeError(result.errorKey, t));
			return;
		}

		setConfirming(false);
		onCleared();
	}

	return (
		<div className="flex items-center gap-2 flex-wrap">
			{!confirming ? (
				<button type="button" className={BTN_GHOST} onClick={() => setConfirming(true)}>
					<TrashIcon width={14} height={14} /> {t('history.clear')}
				</button>
			) : (
				<>
					<span className="text-xs text-[var(--tb-text-muted)]">{t('history.confirm')}</span>
					<button type="button" className={BTN_DANGER} onClick={clear} disabled={busy}>{t('history.yes')}</button>
					<button type="button" className={BTN_GHOST} onClick={() => setConfirming(false)} disabled={busy}>{t('history.cancel')}</button>
				</>
			)}
			{error && <span className={FORM_ERROR}>{error}</span>}
		</div>
	);
}
