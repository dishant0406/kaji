import type { PermissionStoredDecisionSnapshot } from "./permission-types";

export const PERMISSION_DECISION_CUSTOM_TYPE = "kaji.permission_decision";

export interface PermissionDecisionPersistence {
	load(): PermissionStoredDecisionSnapshot[];
	save(decision: PermissionStoredDecisionSnapshot): void | Promise<void>;
}

interface PermissionDecisionSessionLog {
	getEntries(): Array<{ type: string; customType?: string; data?: unknown }>;
	appendCustomEntry(customType: string, data?: unknown): string;
}

export function createSessionPermissionDecisionPersistence(
	sessionLog: PermissionDecisionSessionLog,
): PermissionDecisionPersistence {
	return {
		load: () => loadPermissionDecisionsFromEntries(sessionLog.getEntries()),
		save: decision => {
			sessionLog.appendCustomEntry(PERMISSION_DECISION_CUSTOM_TYPE, decision);
		},
	};
}

export function loadPermissionDecisionsFromEntries(
	entries: Array<{ type: string; customType?: string; data?: unknown }>,
): PermissionStoredDecisionSnapshot[] {
	const byKey = new Map<string, PermissionStoredDecisionSnapshot>();
	for (const entry of entries) {
		if (entry.type !== "custom" || entry.customType !== PERMISSION_DECISION_CUSTOM_TYPE) continue;
		const decision = parseDecision(entry.data);
		if (!decision) continue;
		byKey.set(decision.cacheKey, decision);
	}
	return [...byKey.values()];
}

function parseDecision(value: unknown): PermissionStoredDecisionSnapshot | undefined {
	if (!value || typeof value !== "object" || Array.isArray(value)) return undefined;
	const data = value as Record<string, unknown>;
	const cacheKey = typeof data.cacheKey === "string" ? data.cacheKey : undefined;
	const decision = data.decision === "allow" || data.decision === "deny" ? data.decision : undefined;
	const duration = data.duration === "session" || data.duration === "always" ? data.duration : undefined;
	const createdAt = typeof data.createdAt === "string" ? data.createdAt : undefined;
	const updatedAt = typeof data.updatedAt === "string" ? data.updatedAt : undefined;
	if (!cacheKey || !decision || !duration || !createdAt || !updatedAt) return undefined;
	return { cacheKey, decision, duration, createdAt, updatedAt };
}
