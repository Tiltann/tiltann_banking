import { useEffect } from 'react';
import type { ReactNode } from 'react';
import { AnimatePresence, LayoutGroup, motion, useReducedMotion } from 'motion/react';

export interface SubNavItem<K extends string> {
	key: K;
	label: string;
	icon: ReactNode;
	badge?: number;
}

interface SubNavProps<K extends string> {
	/** Unique per rail instance, scopes the sliding highlight's layoutId. */
	id: string;
	items: SubNavItem<K>[];
	active: K;
	onChange: (key: K) => void;
}

export const SPRING = { type: 'spring', stiffness: 420, damping: 36 } as const;

/**
 * The left navigation rail inside a main tab (pefcl's sidebar): one entry
 * per page. The active highlight is one shared element that slides between
 * entries (SmoothUI-style) instead of two pills swapping. Collapses to a
 * horizontal strip on narrow widths.
 */
export function SubNav<K extends string>({ id, items, active, onChange }: SubNavProps<K>) {
	return (
		<LayoutGroup id={id}>
			<nav className="flex flex-col gap-0.5 max-[760px]:flex-row max-[760px]:flex-wrap">
				{items.map((item) => {
					const isActive = active === item.key;

					return (
						<button
							key={item.key}
							type="button"
							onClick={() => onChange(item.key)}
							className={`relative flex items-center gap-2.5 rounded-lg px-3 py-2 text-[13px] text-left cursor-pointer transition-colors ${
								isActive ? 'text-[var(--tb-text-primary)] font-medium' : 'text-[var(--tb-text-muted)] hover:text-[var(--tb-text-primary)]'
							}`}
						>
							{isActive && <motion.span layoutId="rail-active" transition={SPRING} className="absolute inset-0 rounded-lg bg-[var(--tb-surface)]" />}
							<span className={`relative z-10 ${isActive ? 'text-[var(--tb-accent)]' : ''}`}>{item.icon}</span>
							<span className="relative z-10 flex-1 truncate">{item.label}</span>
							{item.badge ? (
								<span className="relative z-10 min-w-[18px] h-[18px] px-1 rounded-full bg-[var(--tb-danger)] text-[var(--tb-primary)] text-[10px] font-semibold inline-flex items-center justify-center">
									{item.badge}
								</span>
							) : null}
						</button>
					);
				})}
			</nav>
		</LayoutGroup>
	);
}

interface RailLayoutProps {
	nav: ReactNode;
	/** Changes when the page changes, drives the crossfade. */
	pageKey: string;
	children: ReactNode;
}

/** Two-column shell: the rail on the left, the active page on the right, pages crossfading as they swap. */
export function RailLayout({ nav, pageKey, children }: RailLayoutProps) {
	const reduceMotion = useReducedMotion();

	// A new page starts at the top, the tablet screen is one scroll
	// container shared by every page, so it would otherwise keep the previous
	// page's scroll offset.
	useEffect(() => {
		document.querySelector('[data-tb-scroll]')?.scrollTo({ top: 0 });
	}, [pageKey]);

	return (
		<div className="grid [grid-template-columns:200px_minmax(0,1fr)] gap-6 max-[760px]:grid-cols-1 max-[760px]:gap-4">
			{nav}
			<AnimatePresence mode="wait" initial={false}>
				<motion.div
					key={pageKey}
					className="flex flex-col gap-5 min-w-0"
					initial={reduceMotion ? false : { opacity: 0, y: 6 }}
					animate={{ opacity: 1, y: 0 }}
					exit={reduceMotion ? undefined : { opacity: 0, y: -4 }}
					transition={{ duration: 0.16, ease: 'easeOut' }}
				>
					{children}
				</motion.div>
			</AnimatePresence>
		</div>
	);
}
