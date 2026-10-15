const STORAGE_KEY = 'tiltann_banking:accent';

/** A handful of curated presets rather than a free color picker, keeps the palette restrained instead of letting a viewer pick something that clashes with the rest of Config.UI.Colors. */
export const ACCENT_PRESETS = ['#4f8cff', '#3ecf8e', '#c084fc', '#f97066', '#f5a623'];

export function readStoredAccent(): string | null {
	try {
		return localStorage.getItem(STORAGE_KEY);
	} catch {
		return null;
	}
}

export function writeStoredAccent(color: string): void {
	try {
		localStorage.setItem(STORAGE_KEY, color);
	} catch {
		// Cosmetic preference only, fine if it doesn't persist.
	}
}

/** Applies a per-viewer accent override on top of whatever state/theme.ts just set from Config.UI.Colors. */
export function applyAccentOverride(color: string): void {
	document.documentElement.style.setProperty('--tb-accent', color);
}
