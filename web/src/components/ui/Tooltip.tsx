import { useRef, useState } from 'react';
import type { ReactNode } from 'react';
import {
	FloatingArrow,
	FloatingPortal,
	arrow,
	autoUpdate,
	flip,
	offset,
	shift,
	useDismiss,
	useFloating,
	useFocus,
	useHover,
	useInteractions,
	useRole,
} from '@floating-ui/react';
import { AnimatePresence, motion } from 'motion/react';
import type { Placement } from '@floating-ui/react';

interface TooltipProps {
	content: ReactNode;
	children: ReactNode;
	side?: Placement;
	/** Classes for the inline wrapper around the trigger. */
	className?: string;
}

/**
 * Floating tooltip (unlumen-style): positioned by Floating UI so it never
 * clips inside the scrolling tablet screen, springs in through Motion, and
 * shows on hover or keyboard focus. The trigger is wrapped in a span so any
 * child works without ref forwarding.
 */
export function Tooltip({ content, children, side = 'top', className = 'inline-flex' }: TooltipProps) {
	const [open, setOpen] = useState(false);
	const arrowRef = useRef<SVGSVGElement>(null);

	const { refs, floatingStyles, context } = useFloating({
		open,
		onOpenChange: setOpen,
		placement: side,
		whileElementsMounted: autoUpdate,
		middleware: [offset(8), flip(), shift({ padding: 8 }), arrow({ element: arrowRef })],
	});

	const { getReferenceProps, getFloatingProps } = useInteractions([
		useHover(context, { move: false, delay: { open: 220, close: 40 } }),
		useFocus(context),
		useDismiss(context),
		useRole(context, { role: 'tooltip' }),
	]);

	return (
		<>
			<span ref={refs.setReference} {...getReferenceProps()} className={className}>
				{children}
			</span>
			<FloatingPortal>
				<AnimatePresence>
					{open && (
						<div ref={refs.setFloating} style={floatingStyles} {...getFloatingProps()} className="z-50 pointer-events-none">
							<motion.div
								initial={{ opacity: 0, scale: 0.94, y: 3 }}
								animate={{ opacity: 1, scale: 1, y: 0 }}
								exit={{ opacity: 0, scale: 0.96, y: 2 }}
								transition={{ type: 'spring', stiffness: 520, damping: 34 }}
								className="max-w-[240px] rounded-lg bg-[var(--tb-text-primary)] text-[var(--tb-primary)] px-2.5 py-1.5 text-[12px] leading-snug font-medium shadow-[0_8px_24px_rgba(0,0,0,0.35)]"
							>
								{content}
								<FloatingArrow ref={arrowRef} context={context} fill="var(--tb-text-primary)" width={10} height={5} />
							</motion.div>
						</div>
					)}
				</AnimatePresence>
			</FloatingPortal>
		</>
	);
}
