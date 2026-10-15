import { useEffect, useRef } from 'react';
import { useMotionValue, useReducedMotion, useSpring } from 'motion/react';

interface NumberTickerProps {
	value: number;
	/** Turns the animated number into display text, e.g. formatMoney. */
	format: (value: number) => string;
	className?: string;
}

/**
 * MagicUI-style number ticker: the figure springs from its previous value
 * to the new one instead of snapping, so a balance visibly changes after a
 * deposit. Writes to the DOM node directly (no re-render per frame). Honors
 * prefers-reduced-motion by rendering the final value immediately.
 */
export function NumberTicker({ value, format, className }: NumberTickerProps) {
	const ref = useRef<HTMLSpanElement>(null);
	const reduceMotion = useReducedMotion();
	const motionValue = useMotionValue(reduceMotion ? value : 0);
	const spring = useSpring(motionValue, { stiffness: 190, damping: 32, mass: 0.8 });

	useEffect(() => {
		motionValue.set(value);
	}, [motionValue, value]);

	useEffect(() => {
		const write = (current: number) => {
			if (ref.current) {
				ref.current.textContent = format(Math.round(current));
			}
		};

		write(spring.get());
		return spring.on('change', write);
	}, [spring, format]);

	return (
		<span ref={ref} className={className}>
			{format(reduceMotion ? value : 0)}
		</span>
	);
}
