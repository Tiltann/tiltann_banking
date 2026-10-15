import {
	MOCK_ATM_SESSION,
	MOCK_BUSINESS,
	MOCK_BUSINESS_TRANSACTIONS,
	MOCK_CARDS,
	MOCK_PERSONAL,
	MOCK_PERSONAL_TRANSACTIONS,
	MOCK_GRADE_ROLES,
	MOCK_STAFF,
	MOCK_TAX,
	MOCK_TERMINAL_PAYLOAD,
} from './fixtures';
import type { TbTransaction } from '../types';

declare global {
	interface Window {
		GetParentResourceName?: () => string;
	}
}

export const IS_BROWSER_PREVIEW = typeof window.GetParentResourceName !== 'function';

/**
 * Posts to a client-side `RegisterNUICallback` (see client/ui/bank_ui.lua).
 * In the real NUI runtime this hits FiveM's local resource server; in a
 * plain browser (screenshots/previews with no game client) it resolves
 * canned fixture data instead of failing outright.
 */
export async function fetchNui<T>(eventName: string, data?: unknown): Promise<T> {
	if (IS_BROWSER_PREVIEW) {
		return mockNuiResponse<T>(eventName, data);
	}

	const resourceName = window.GetParentResourceName!();
	const response = await fetch(`https://${resourceName}/${eventName}`, {
		method: 'POST',
		headers: { 'Content-Type': 'application/json; charset=UTF-8' },
		body: JSON.stringify(data ?? {}),
	});

	return response.json() as Promise<T>;
}

function page(all: TbTransaction[], data?: unknown): TbTransaction[] {
	const offset = (data as { offset?: number } | undefined)?.offset ?? 0;
	return offset === 0 ? all : [];
}

function mockNuiResponse<T>(eventName: string, data?: unknown): Promise<T> {
	const resolve = (value: unknown) => Promise.resolve(value as T);
	const accountId = (data as { accountId?: number } | undefined)?.accountId;

	switch (eventName) {
		case 'tiltann_banking:ui:atm:unlock':
		case 'tiltann_banking:ui:atm:getSession':
			return resolve({ ok: true, session: MOCK_ATM_SESSION });

		case 'tiltann_banking:ui:personal:get':
			return resolve(MOCK_PERSONAL);

		case 'tiltann_banking:ui:transactions':
			return resolve(page(accountId === 4 ? MOCK_BUSINESS_TRANSACTIONS : MOCK_PERSONAL_TRANSACTIONS, data));

		case 'tiltann_banking:ui:business:list':
			return resolve(MOCK_TERMINAL_PAYLOAD.businesses);

		case 'tiltann_banking:ui:business:get':
			return resolve(MOCK_BUSINESS);

		case 'tiltann_banking:ui:business:listGradeRoles':
			return resolve(MOCK_GRADE_ROLES);

		case 'tiltann_banking:ui:business:listMembers':
			return resolve({ allowed: true, members: MOCK_STAFF });

		case 'tiltann_banking:ui:billing:getOpen':
			return resolve(accountId === 4 ? MOCK_BUSINESS.openInvoices : { incoming: MOCK_PERSONAL.openInvoices, outgoing: [] });

		case 'tiltann_banking:ui:billing:getNearby':
			return resolve([
				{ id: 12, name: 'Max Mustermann' },
				{ id: 27, name: 'Erika Beispiel' },
			]);

		case 'tiltann_banking:ui:billing:send':
			return resolve({ ok: true });

		case 'tiltann_banking:ui:orders:list':
			return resolve(accountId === 4 ? MOCK_BUSINESS.standingOrders : MOCK_PERSONAL.standingOrders);

		case 'tiltann_banking:ui:cards:list':
			return resolve(MOCK_CARDS);

		case 'tiltann_banking:ui:tax:get':
			return resolve(MOCK_TAX);

		case 'tiltann_banking:ui:cards:toggleLock':
			return resolve({ ok: true, value: true });

		case 'tiltann_banking:ui:cards:request':
			return resolve({ ok: true, value: 99 });

		default:
			return resolve({ ok: true });
	}
}
