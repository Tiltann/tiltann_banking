// The UI texts live in locales/ui/<code>.json (next to the other locales) and
// are sent along when the UI opens, so a text can be changed without
// rebuilding. To add a language, copy en.json, translate it and set
// "lang.name" to its display name.

export type Lang = string;

export type Translations = Record<Lang, Record<string, string>>;

export function languagesOf(translations: Translations): { value: Lang; label: string }[] {
	return Object.keys(translations).map((code) => ({ value: code, label: translations[code]['lang.name'] ?? code }));
}
