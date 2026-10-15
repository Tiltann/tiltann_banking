import type { TbUiColors } from '../types';

// One CSS custom property per Config.UI.Colors key, see config/config.ui.lua.
// Reskinning the tablet server-side means changing zero lines here.
export function applyTheme(colors: TbUiColors): void {
	const root = document.documentElement.style;

	root.setProperty('--tb-primary', colors.primary);
	root.setProperty('--tb-secondary', colors.secondary);
	root.setProperty('--tb-accent', colors.accent);
	root.setProperty('--tb-background', colors.background);
	root.setProperty('--tb-surface', colors.surface);
	root.setProperty('--tb-text-primary', colors.textPrimary);
	root.setProperty('--tb-text-muted', colors.textMuted);
	root.setProperty('--tb-success', colors.success);
	root.setProperty('--tb-danger', colors.danger);
	root.setProperty('--tb-warning', colors.warning);
}
