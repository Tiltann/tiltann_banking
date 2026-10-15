import { useEffect, useState } from 'react';
import { useTranslation } from '../i18n/context';
import { ACCENT_PRESETS, applyAccentOverride, writeStoredAccent } from '../state/accent';
import { CheckIcon, GearIcon, GlobeIcon, PaletteIcon } from '../icons';
import { ICON_BTN } from '../ui-classes';

interface SettingsPanelProps {
	accent: string;
	onAccentChange: (color: string) => void;
}

/**
 * Gear-icon settings popover: language and accent color are per-viewer
 * preferences stored in this browser's localStorage (see i18n/context.tsx
 * and state/accent.ts), they never touch the server, so Config.UI's own
 * DefaultLanguage/Colors stay the source of truth for anyone who hasn't
 * chosen an override yet.
 */
export function SettingsPanel({ accent, onAccentChange }: SettingsPanelProps) {
	const [open, setOpen] = useState(false);
	const { lang, languages, setLang, t } = useTranslation();

	// Escape closes this popover instead of the whole tablet. Capture phase so
	// it runs before App.tsx's own Escape handler no matter which mounted
	// first; preventDefault is how that handler is told the key was consumed.
	useEffect(() => {
		if (!open) {
			return;
		}

		function handleKeyDown(event: KeyboardEvent) {
			if (event.key !== 'Escape') {
				return;
			}

			event.preventDefault();
			setOpen(false);
		}

		window.addEventListener('keydown', handleKeyDown, { capture: true });
		return () => window.removeEventListener('keydown', handleKeyDown, { capture: true });
	}, [open]);

	function pickAccent(color: string) {
		applyAccentOverride(color);
		writeStoredAccent(color);
		onAccentChange(color);
	}

	return (
		<div className="relative">
			<button type="button" className={`${ICON_BTN} ${open ? 'bg-[var(--tb-surface)] text-[var(--tb-text-primary)]' : ''}`} aria-label={t('common.settings')} onClick={() => setOpen((current) => !current)}>
				<GearIcon width={16} height={16} />
			</button>

			{open && (
				<div className="absolute top-[calc(100%+6px)] right-0 w-[230px] bg-[var(--tb-surface)] rounded-xl p-4 flex flex-col gap-4 shadow-[0_16px_40px_rgba(0,0,0,0.45)] z-10">
					<div className="flex flex-col gap-2">
						<span className="flex items-center gap-1.5 text-[11px] uppercase tracking-[0.08em] text-[var(--tb-text-muted)]">
							<GlobeIcon width={13} height={13} /> {t('settings.language')}
						</span>
						<div className="flex gap-1 bg-[var(--tb-primary)] rounded-lg p-1">
							{languages.map((option) => (
								<button
									key={option.value}
									type="button"
									className={`flex-1 rounded-md px-2 py-1.5 text-xs cursor-pointer transition-colors ${
										lang === option.value ? 'bg-[var(--tb-surface)] text-[var(--tb-text-primary)] font-medium' : 'text-[var(--tb-text-muted)] hover:text-[var(--tb-text-primary)]'
									}`}
									onClick={() => setLang(option.value)}
								>
									{option.label}
								</button>
							))}
						</div>
					</div>

					<div className="flex flex-col gap-2">
						<span className="flex items-center gap-1.5 text-[11px] uppercase tracking-[0.08em] text-[var(--tb-text-muted)]">
							<PaletteIcon width={13} height={13} /> {t('settings.accentColor')}
						</span>
						<div className="flex gap-2">
							{ACCENT_PRESETS.map((color) => (
								<button
									key={color}
									type="button"
									className={`w-7 h-7 rounded-full cursor-pointer flex items-center justify-center transition-transform hover:scale-110 ${accent === color ? 'shadow-[0_0_0_2px_var(--tb-surface),0_0_0_3.5px_var(--tb-text-primary)]' : ''}`}
									style={{ background: color }}
									aria-label={color}
									onClick={() => pickAccent(color)}
								>
									{accent === color && <CheckIcon width={14} height={14} stroke="#111" />}
								</button>
							))}
						</div>
					</div>
				</div>
			)}
		</div>
	);
}
