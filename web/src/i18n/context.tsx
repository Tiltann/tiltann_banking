import { createContext, useCallback, useContext, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import { languagesOf, type Lang, type Translations } from './strings';

const STORAGE_KEY = 'tiltann_banking:lang';

export type TranslateFn = (key: string, vars?: Record<string, string | number>) => string;

interface LanguageContextValue {
	lang: Lang;
	languages: { value: Lang; label: string }[];
	setLang: (lang: Lang) => void;
	t: TranslateFn;
}

const LanguageContext = createContext<LanguageContextValue | null>(null);

function readStoredLang(available: Translations): Lang | null {
	try {
		const stored = localStorage.getItem(STORAGE_KEY);
		return stored && available[stored] ? stored : null;
	} catch {
		return null;
	}
}

function writeStoredLang(lang: Lang): void {
	try {
		localStorage.setItem(STORAGE_KEY, lang);
	} catch {
		// Cosmetic preference only, fine if it doesn't persist.
	}
}

/**
 * Language context seeded from the player's last choice (localStorage,
 * per-viewer) or, if they've never picked one, the server's
 * Config.UI.DefaultLanguage. `t` supports `{name}` placeholders.
 */
export function LanguageProvider({ defaultLanguage, translations, children }: { defaultLanguage: Lang; translations: Translations; children: ReactNode }) {
	const [lang, setLangState] = useState<Lang>(() => readStoredLang(translations) ?? defaultLanguage);
	const languages = useMemo(() => languagesOf(translations), [translations]);

	const setLang = useCallback((next: Lang) => {
		setLangState(next);
		writeStoredLang(next);
	}, []);

	const t = useCallback<TranslateFn>(
		(key, vars) => {
			let text = translations[lang]?.[key] ?? translations.en?.[key] ?? key;

			if (vars) {
				for (const [name, value] of Object.entries(vars)) {
					text = text.replace(`{${name}}`, String(value));
				}
			}

			return text;
		},
		[lang, translations]
	);

	const value = useMemo(() => ({ lang, languages, setLang, t }), [lang, languages, setLang, t]);

	return <LanguageContext.Provider value={value}>{children}</LanguageContext.Provider>;
}

export function useTranslation(): LanguageContextValue {
	const context = useContext(LanguageContext);

	if (!context) {
		throw new Error('useTranslation must be used within a LanguageProvider');
	}

	return context;
}
