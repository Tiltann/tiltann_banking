import { useEffect, useState } from 'react';
import type { ActionResult, TbCapabilities, TbGradeRole, TbGradeRoleView, TbRole, TbStaffMember } from '../types';
import { fetchNui } from '../api/nui';
import { describeError } from '../errorMessages';
import { useTranslation } from '../i18n/context';
import { formatMoney } from '../format';
import { TrashIcon } from '../icons';
import { BADGE, BTN_GHOST, BTN_PRIMARY, FIELD_LABEL, FORM_ERROR, INPUT, NOTE, PANEL, PANEL_TITLE, SELECT } from '../ui-classes';

interface StaffPanelProps {
	accountId: number;
	ownRole: TbRole;
	currencySymbol: string;
}

const ROLE_RANK: Record<TbRole, number> = { contributor: 1, admin: 2, owner: 3 };
const ROLES: TbRole[] = ['contributor', 'admin', 'owner'];

/** The capability flags, in the order they are worth reading. */
const CAPABILITY_KEYS: (keyof TbCapabilities)[] = ['view', 'deposit', 'withdraw', 'invoice', 'manageStaff', 'delete'];

/**
 * Who may touch this business's money, on two independent tracks:
 *
 * , RANKS: every ESX job grade maps to a role, so a whole rank gets access
 *    without anyone adding its members one by one. The job's highest grade
 *    is pinned to owner by Config.Society.HighestGradeIsOwner, which is what
 *    stops a boss locking themselves out, shown as fixed rather than as a
 *    control that would be ignored.
 * , PEOPLE: individuals added by their online server id, for anyone the
 *    rank rules do not already cover.
 *
 * Every change is re-checked server-side (server/society/members.lua) and
 * nobody can hand out a role above their own.
 */
export function StaffPanel({ accountId, ownRole, currencySymbol }: StaffPanelProps) {
	const { t } = useTranslation();
	const [members, setMembers] = useState<TbStaffMember[] | null>(null);
	const [grades, setGrades] = useState<TbGradeRoleView | null>(null);
	const [serverId, setServerId] = useState('');
	const [role, setRole] = useState<TbRole>('contributor');
	const [limits, setLimits] = useState<Record<string, string>>({});
	const [error, setError] = useState<string | undefined>(undefined);
	const [busy, setBusy] = useState(false);

	const assignable = ROLES.filter((candidate) => ROLE_RANK[candidate] <= ROLE_RANK[ownRole]);

	async function load() {
		const [staff, gradeView] = await Promise.all([
			fetchNui<{ allowed: boolean; members?: TbStaffMember[] }>('tiltann_banking:ui:business:listMembers', { accountId }),
			fetchNui<TbGradeRoleView>('tiltann_banking:ui:business:listGradeRoles', { accountId }),
		]);

		setMembers(staff.members ?? []);
		setGrades(gradeView);
	}

	useEffect(() => {
		load();
	}, [accountId]);

	async function run(action: () => Promise<ActionResult>) {
		setBusy(true);
		setError(undefined);

		const result = await action();

		setBusy(false);

		if (!result.ok) {
			setError(describeError(result.errorKey, t));
			return false;
		}

		await load();
		return true;
	}

	async function add() {
		const parsed = Number(serverId);

		if (!Number.isInteger(parsed) || parsed <= 0) {
			return;
		}

		const ok = await run(() => fetchNui('tiltann_banking:ui:business:addMember', { accountId, serverId: parsed, role }));

		if (ok) {
			setServerId('');
		}
	}

	function saveLimit(member: TbStaffMember) {
		const raw = limits[member.identifier];
		const limit = raw === undefined || raw === '' ? null : Math.floor(Number(raw));

		run(() => fetchNui('tiltann_banking:ui:business:setMemberCardLimit', { accountId, identifier: member.identifier, limit }));
	}

	const capabilities = grades?.capabilities;

	return (
		<>
			{error && <p className={FORM_ERROR}>{error}</p>}

			{/* What each role actually means, next to the pickers that set it,
			    otherwise "admin" is a word with no consequences attached. */}
			{capabilities && (
				<section className={PANEL}>
					<h2 className={PANEL_TITLE}>{t('staff.roleLegend')}</h2>
					<div className="grid [grid-template-columns:repeat(auto-fit,minmax(200px,1fr))] gap-4">
						{ROLES.map((candidate) => (
							<div key={candidate} className="flex flex-col gap-1.5">
								<span className={`${BADGE.accent} self-start`}>{t(`business.role.${candidate}`)}</span>
								<ul className="m-0 pl-0 list-none flex flex-col gap-0.5">
									{CAPABILITY_KEYS.filter((key) => capabilities[candidate]?.[key]).map((key) => (
										<li key={key} className="text-[12px] text-[var(--tb-text-muted)]">· {t(`cap.${key}`)}</li>
									))}
								</ul>
							</div>
						))}
					</div>
				</section>
			)}

			<section className={PANEL}>
				<h2 className={PANEL_TITLE}>{t('staff.grades')}</h2>

				{!grades?.jobName ? (
					<p className={NOTE}>{t('staff.gradesNoJob')}</p>
				) : (
					<>
						<p className={NOTE}>{t('staff.gradesHint')}</p>
						<div className="flex flex-col">
							{(grades.grades ?? []).map((entry: TbGradeRole) => (
								<div key={entry.grade} className="flex items-center justify-between gap-3 py-2.5 border-b border-[var(--tb-secondary)]/60 last:border-b-0 flex-wrap">
									<div className="flex flex-col gap-0.5 min-w-0">
										<span className="text-[13px] truncate">{entry.label}</span>
										<span className="text-[11px] tabular-nums text-[var(--tb-text-muted)]">#{entry.grade}</span>
									</div>
									{entry.isHighest ? (
										<div className="flex items-center gap-2">
											<span className={BADGE.accent}>{t('business.role.owner')}</span>
											<span className="text-[11px] text-[var(--tb-text-muted)]">{t('staff.highestFixed')}</span>
										</div>
									) : (
										<select
											className={SELECT}
											value={entry.role}
											disabled={busy || ROLE_RANK[entry.role] > ROLE_RANK[ownRole]}
											onChange={(e) => run(() => fetchNui('tiltann_banking:ui:business:setGradeRole', { accountId, grade: entry.grade, role: e.target.value }))}
										>
											{assignable.map((candidate) => (
												<option key={candidate} value={candidate}>{t(`business.role.${candidate}`)}</option>
											))}
										</select>
									)}
								</div>
							))}
						</div>
					</>
				)}
			</section>

			<section className={PANEL}>
				<h2 className={PANEL_TITLE}>{t('staff.members')}</h2>

				{members === null ? (
					<p className={NOTE}>{t('common.loading')}</p>
				) : members.length === 0 ? (
					<p className={NOTE}>{t('staff.none')}</p>
				) : (
					<div className="flex flex-col">
						{members.map((member) => {
							const canEdit = ROLE_RANK[member.role] <= ROLE_RANK[ownRole];

							return (
								<div key={member.identifier} className="flex items-center justify-between gap-3 py-2.5 border-b border-[var(--tb-secondary)]/60 last:border-b-0 flex-wrap">
									<div className="flex flex-col gap-0.5 min-w-0">
										<span className="text-[13px] truncate">{member.name || t('staff.unknownName')}</span>
										{member.serverId ? (
											<span className="text-[11px] tabular-nums text-[var(--tb-success)]">
												{t('staff.serverId')} {member.serverId} · {t('staff.online')}
											</span>
										) : null}
									</div>
									<div className="flex items-center gap-2 flex-wrap">
										{canEdit ? (
											<select
												className={SELECT}
												value={member.role}
												disabled={busy}
												onChange={(e) => run(() => fetchNui('tiltann_banking:ui:business:setMemberRole', { accountId, identifier: member.identifier, role: e.target.value }))}
											>
												{assignable.map((candidate) => (
													<option key={candidate} value={candidate}>{t(`business.role.${candidate}`)}</option>
												))}
											</select>
										) : (
											<span className={BADGE.neutral}>{t(`business.role.${member.role}`)}</span>
										)}
										<input
											className={`${INPUT} max-w-[130px]`}
											type="number"
											min={0}
											placeholder={member.cardDailyLimit === null ? t('staff.limitDefault') : formatMoney(member.cardDailyLimit, currencySymbol)}
											value={limits[member.identifier] ?? ''}
											onChange={(e) => setLimits((current) => ({ ...current, [member.identifier]: e.target.value }))}
											onBlur={() => limits[member.identifier] !== undefined && saveLimit(member)}
											disabled={busy || !canEdit}
											title={t('staff.limit')}
										/>
										{canEdit && (
											<button type="button" className={BTN_GHOST} onClick={() => run(() => fetchNui('tiltann_banking:ui:business:removeMember', { accountId, identifier: member.identifier }))} disabled={busy}>
												<TrashIcon width={14} height={14} /> {t('staff.remove')}
											</button>
										)}
									</div>
								</div>
							);
						})}
					</div>
				)}

				<div className="flex flex-wrap gap-2 items-end pt-2 border-t border-[var(--tb-secondary)]/60">
					<label className={`${FIELD_LABEL} w-[130px]`}>
						{t('staff.serverId')}
						<input
							className={INPUT}
							type="number"
							min={1}
							placeholder="12"
							value={serverId}
							onChange={(e) => setServerId(e.target.value)}
							onKeyDown={(e) => e.key === 'Enter' && add()}
							disabled={busy}
						/>
					</label>
					<label className={FIELD_LABEL}>
						{t('staff.role')}
						<select className={SELECT} value={role} onChange={(e) => setRole(e.target.value as TbRole)} disabled={busy}>
							{assignable.map((candidate) => (
								<option key={candidate} value={candidate}>{t(`business.role.${candidate}`)}</option>
							))}
						</select>
					</label>
					<button type="button" className={BTN_PRIMARY} onClick={add} disabled={busy || serverId.trim() === ''}>
						{t('staff.add')}
					</button>
					<p className={`${NOTE} basis-full text-xs`}>{t('staff.serverIdHint')}</p>
				</div>
			</section>
		</>
	);
}
