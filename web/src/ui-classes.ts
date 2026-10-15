// Shared Tailwind utility strings for the recurring patterns (buttons,
// inputs, panels, badges), centralized so every component draws from the
// same tokens instead of retyping long arbitrary-value strings. Colors are
// all CSS custom properties (see index.css) since the palette is only known
// at runtime, see config/config.ui.lua.

/** A content block: filled surface, no border, the border is reserved for inputs so nesting never reads as boxes-in-boxes. */
export const PANEL = 'bg-[var(--tb-surface)] rounded-xl px-5 py-4 flex flex-col gap-3.5';

export const PANEL_TITLE = 'flex items-center gap-2 m-0 text-[12px] font-semibold uppercase tracking-[0.08em] text-[var(--tb-text-muted)]';

export const INPUT = 'bg-[var(--tb-primary)] border border-[var(--tb-secondary)] rounded-lg text-[var(--tb-text-primary)] px-3 py-2 text-[13px] min-w-0 flex-1 placeholder:text-[var(--tb-text-muted)] focus:outline-none focus:border-[var(--tb-accent)] disabled:opacity-60';

export const SELECT = 'bg-[var(--tb-primary)] border border-[var(--tb-secondary)] rounded-lg text-[var(--tb-text-primary)] px-3 py-2 text-[13px] cursor-pointer focus:outline-none focus:border-[var(--tb-accent)] disabled:opacity-60';

const BTN_BASE = 'inline-flex items-center justify-center gap-1.5 rounded-lg px-3.5 py-2 text-[13px] font-medium cursor-pointer border border-transparent transition-colors whitespace-nowrap disabled:opacity-50 disabled:cursor-default';

export const BTN_PRIMARY = `${BTN_BASE} bg-[var(--tb-accent)] text-[var(--tb-primary)] hover:opacity-90`;

// Full-strength text, not the muted token: on the grey button fill that read
// as grey-on-grey and the labels were barely legible. The button is still
// visually secondary through its flat fill, which is what "ghost" is for.
// It does not need washed-out text on top of that.
export const BTN_GHOST = `${BTN_BASE} bg-[var(--tb-primary)] text-[var(--tb-text-primary)] hover:bg-[var(--tb-secondary)]`;

export const BTN_DANGER = `${BTN_BASE} bg-[var(--tb-primary)] text-[var(--tb-danger)] hover:bg-[var(--tb-danger)] hover:text-[var(--tb-primary)]`;

/** Square icon-only button (settings gear, close). */
export const ICON_BTN = 'inline-flex items-center justify-center w-9 h-9 rounded-lg bg-transparent text-[var(--tb-text-muted)] cursor-pointer transition-colors hover:bg-[var(--tb-surface)] hover:text-[var(--tb-text-primary)]';

/** Page heading at the top of a rail page. */
export const PAGE_TITLE = 'm-0 text-[20px] font-semibold tracking-tight';

/** Small uppercase label above a form field. */
export const FIELD_LABEL = 'flex flex-col gap-1.5 text-[11px] uppercase tracking-[0.08em] text-[var(--tb-text-muted)] min-w-0';

export const FORM_ERROR = 'text-[var(--tb-danger)] text-xs m-0';

export const NOTE = 'm-0 text-[13px] text-[var(--tb-text-muted)]';

/** Hairline row inside a panel list. */
export const ROW = 'flex items-center justify-between gap-3 py-2.5 border-b border-[var(--tb-secondary)]/60 last:border-b-0';

const BADGE_BASE = 'text-[10px] font-semibold uppercase tracking-[0.06em] px-2 py-[3px] rounded-md';

// A badge tinted with its own colour AND lettered in that same colour was
// the accent-on-accent problem: at 16% tint the blue "OWNER" text sat on a
// blue ground and all but vanished. The ground stays tinted, but the text is
// mixed toward white so it keeps its hue and still carries real contrast,
// which works for any accent an owner configures, not just the default.
const BADGE_TINT = (token: string) =>
	`${BADGE_BASE} bg-[color-mix(in_srgb,var(${token})_22%,transparent)] text-[color-mix(in_srgb,var(${token})_55%,white)]`;

export const BADGE: Record<'success' | 'warning' | 'danger' | 'neutral' | 'accent', string> = {
	success: BADGE_TINT('--tb-success'),
	warning: BADGE_TINT('--tb-warning'),
	danger: BADGE_TINT('--tb-danger'),
	neutral: `${BADGE_BASE} bg-[color-mix(in_srgb,var(--tb-text-muted)_20%,transparent)] text-[var(--tb-text-primary)]`,
	accent: BADGE_TINT('--tb-accent'),
};
