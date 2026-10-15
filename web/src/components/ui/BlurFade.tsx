import type { ReactNode } from 'react';
import { motion, useReducedMotion } from 'motion/react';

interface BlurFadeProps {
	children: ReactNode;
	/** Seconds, stagger siblings with index * 0.05. */
	delay?: number;
	className?: string;
}

/** MagicUI-style entry: content fades up out of a slight blur. Used to stagger tiles, rows and panels as a page opens. */
export function BlurFade({ children, delay = 0, className }: BlurFadeProps) {
	const reduceMotion = useReducedMotion();

	return (
		<motion.div
			className={className}
			initial={reduceMotion ? false : { opacity: 0, y: 8, filter: 'blur(4px)' }}
			animate={{ opacity: 1, y: 0, filter: 'blur(0px)' }}
			transition={{ duration: 0.32, delay, ease: [0.21, 0.47, 0.32, 0.98] }}
		>
			{children}
		</motion.div>
	);
}
