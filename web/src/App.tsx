import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import { AnimatePresence, LayoutGroup, motion } from 'motion/react';
import { applyTheme } from './state/theme';
import { readStoredAccent, applyAccentOverride } from './state/accent';
import { fetchNui, IS_BROWSER_PREVIEW } from './api/nui';
import { AtmScreen } from './components/AtmScreen';
import { BillingScreen } from './components/BillingScreen';
import { PersonalTab } from './components/PersonalTab';
import { BusinessTab } from './components/BusinessTab';
import { SettingsPanel } from './components/SettingsPanel';
import { SPRING } from './components/SubNav';
import { Tooltip } from './components/ui/Tooltip';
import { LanguageProvider, useTranslation } from './i18n/context';
import { MOCK_BILLING_PAYLOAD, MOCK_TERMINAL_PAYLOAD, loadPreviewTranslations } from './api/fixtures';
import { WalletIcon, BuildingIcon, CloseIcon } from './icons';
import { ICON_BTN } from './ui-classes';
import type { Translations } from './i18n/strings';
import type { BankUiMessage, BankUiOpenPayload, TerminalOpenPayload } from './types';

async function fetchTranslations(defaultLanguage: string): Promise<Translations> {
	const result: Translations = {};
	const resource = window.GetParentResourceName?.() ?? 'tiltann_banking';

	for (const code of new Set(['en', defaultLanguage, 'de'])) {
		try {
			const response = await fetch(`https://cfx-nui-${resource}/locales/ui/${code}.json`);

			if (response.ok) {
				result[code] = await response.json();
			}
		} catch {
			// a missing language file just means that language is not offered
		}
	}

	return result;
}

export function App() {
	// Standalone browser preview starts pre-opened with fixture data so the
	// UI is visible immediately for screenshots; inside the real NUI runtime
	// it stays hidden until client/ui/bank_ui.lua's SendNUIMessage arrives.
	const [payload, setPayload] = useState<BankUiOpenPayload | null>(null);
	const [visible, setVisible] = useState(IS_BROWSER_PREVIEW);

	useEffect(() => {
		if (IS_BROWSER_PREVIEW) {
			const mock = new URLSearchParams(window.location.search).get('mode') === 'billing' ? MOCK_BILLING_PAYLOAD : MOCK_TERMINAL_PAYLOAD;
			loadPreviewTranslations().then((translations) => setPayload({ ...mock, translations }));
		}
	}, []);

	useEffect(() => {
		function handleMessage(event: MessageEvent<BankUiMessage>) {
			if (event.data.action === 'open') {
				const opened = event.data;

				applyTheme(opened.colors);

				if (Object.keys(opened.translations ?? {}).length > 0) {
					setPayload(opened);
					setVisible(true);
					return;
				}

				// the game sent no texts, read the language files ourselves
				fetchTranslations(opened.defaultLanguage).then((translations) => {
					setPayload({ ...opened, translations });
					setVisible(true);
				});
			} else if (event.data.action === 'close') {
				setVisible(false);
			} else if (event.data.action === 'refresh') {
				// a balance changed outside the UI, open pages reload themselves
				window.dispatchEvent(new Event('tb:refresh'));
			}
		}

		window.addEventListener('message', handleMessage);
		return () => window.removeEventListener('message', handleMessage);
	}, []);

	useEffect(() => {
		if (payload) {
			applyTheme(payload.colors);

			const storedAccent = readStoredAccent();

			if (storedAccent) {
				applyAccentOverride(storedAccent);
			}
		}
	}, [payload]);

	// Escape closes the tablet / ATM. The client script also polls the game's
	// own Escape control, but that never fires while the NUI holds keyboard
	// focus (SetNuiFocus(true, true)), which is exactly when the player wants
	// to close it, so the browser side has to handle the key itself.
	//
	// `defaultPrevented` lets a layer on top (the settings popover) consume
	// Escape first; it listens in the capture phase, so it always runs before
	// this one regardless of mount order.
	useEffect(() => {
		if (!visible) {
			return;
		}

		function handleKeyDown(event: KeyboardEvent) {
			if (event.key !== 'Escape' || event.defaultPrevented) {
				return;
			}

			fetchNui('tiltann_banking:ui:close');
			setVisible(false);
		}

		window.addEventListener('keydown', handleKeyDown);
		return () => window.removeEventListener('keydown', handleKeyDown);
	}, [visible]);

	useEffect(() => {
		// Real NUI stays transparent over the 3D world; the standalone preview
		// gets a dim backdrop so the device isn't floating on a white page.
		if (IS_BROWSER_PREVIEW) {
			document.body.style.background = 'radial-gradient(circle at 50% 20%, #1a1d24 0%, #0a0b0e 70%)';
			document.body.style.minHeight = '100vh';
		}
	}, []);

	if (!payload) {
		return null;
	}

	return (
		<LanguageProvider defaultLanguage={payload.defaultLanguage} translations={payload.translations}>
			<AnimatePresence>
			{!visible ? null : payload.mode === 'atm' ? (
				<AtmScreen key="atm" payload={payload} onClose={() => setVisible(false)} />
			) : payload.mode === 'billing' ? (
				<BillingScreen key="billing" payload={payload} onClose={() => setVisible(false)} />
			) : (
				<TerminalUi key="terminal" payload={payload} onClose={() => setVisible(false)} />
			)}
			</AnimatePresence>
		</LanguageProvider>
	);
}

type Tab = 'personal' | 'business';

interface TerminalUiProps {
	payload: TerminalOpenPayload;
	onClose: () => void;
}

/**
 * The bank terminal's Main UI, framed as the physical tablet it represents
 * (bezel + camera dot). Personal first; Business only when the player has
 * at least one business. The bezel is only as big as the device itself.
 * The page body stays fully transparent so the 3D world shows through.
 */
function TerminalUi({ payload, onClose }: TerminalUiProps) {
	const { t } = useTranslation();
	const [activeTab, setActiveTab] = useState<Tab>('personal');
	const [accent, setAccent] = useState(() => readStoredAccent() ?? payload.colors.accent);

	function handleClose() {
		fetchNui('tiltann_banking:ui:close');
		onClose();
	}

	const tabs: { key: Tab; label: string; icon: ReactNode }[] =[{ key: 'personal', label: t('tab.personal'), icon: <WalletIcon width={15} height={15} /> }];

	if (payload.businesses.length > 0) {
		tabs.push({ key: 'business', label: t('tab.business'), icon: <BuildingIcon width={15} height={15} /> });
	}

	return (
		<motion.div
			initial={{ opacity: 0, y: 18, scale: 0.985 }}
			animate={{ opacity: 1, y: 0, scale: 1 }}
			exit={{ opacity: 0, y: 24, scale: 0.97, transition: { duration: 0.18, ease: 'easeIn' } }}
			transition={{ type: 'spring', stiffness: 260, damping: 30 }}
			className="w-[min(1040px,94vw)] mx-auto mt-[4vh] rounded-[34px] bg-[linear-gradient(180deg,#2a2c33_0%,#15161a_100%)] p-3 shadow-[0_30px_70px_rgba(0,0,0,0.55),inset_0_1px_0_rgba(255,255,255,0.06)]"
		>
			<div className="flex justify-center pb-2">
				<span className="w-1.5 h-1.5 rounded-full bg-black/50" />
			</div>

			<div className="w-full h-[min(700px,82vh)] bg-[var(--tb-primary)] rounded-[24px] flex flex-col overflow-hidden">
				<header className="flex items-center justify-between gap-4 px-7 pt-5 pb-4 shrink-0">
					<LayoutGroup id="tabs">
						<div className="flex items-center gap-1">
							{tabs.map((tab) => {
								const isActive = activeTab === tab.key;

								return (
									<button
										key={tab.key}
										type="button"
										onClick={() => setActiveTab(tab.key)}
										className={`relative inline-flex items-center gap-2 rounded-lg px-4 py-2 text-[13px] font-medium cursor-pointer transition-colors ${
											isActive ? 'text-[var(--tb-text-primary)]' : 'text-[var(--tb-text-muted)] hover:text-[var(--tb-text-primary)]'
										}`}
									>
										{isActive && <motion.span layoutId="tab-active" transition={SPRING} className="absolute inset-0 rounded-lg bg-[var(--tb-surface)]" />}
										<span className="relative z-10 inline-flex items-center gap-2">
											{tab.icon} {tab.label}
										</span>
									</button>
								);
							})}
						</div>
					</LayoutGroup>

					<div className="flex items-center gap-1.5">
						<SettingsPanel accent={accent} onAccentChange={setAccent} />
						<Tooltip content={t('common.close')} side="bottom">
							<button type="button" className={ICON_BTN} onClick={handleClose} aria-label={t('common.close')}>
								<CloseIcon width={16} height={16} />
							</button>
						</Tooltip>
					</div>
				</header>

				<div data-tb-scroll className="flex-1 min-h-0 overflow-y-auto px-7 pb-7">
					{activeTab === 'personal' ? (
						<PersonalTab businesses={payload.businesses} initial={payload.personal} features={payload.features} currencySymbol={payload.currencySymbol} colors={payload.colors} />
					) : (
						<BusinessTab businesses={payload.businesses} initial={payload.business} features={payload.features} currencySymbol={payload.currencySymbol} colors={payload.colors} />
					)}
				</div>
			</div>
		</motion.div>
	);
}
