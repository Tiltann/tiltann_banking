import { useEffect, useState } from 'react';

/** Re-renders the caller on an interval (default 30s) and returns the current time, for live countdowns. */
export function useNow(intervalMs = 30000): number {
	const [now, setNow] = useState(() => Date.now());

	useEffect(() => {
		const id = setInterval(() => setNow(Date.now()), intervalMs);
		return () => clearInterval(id);
	}, [intervalMs]);

	return now;
}
