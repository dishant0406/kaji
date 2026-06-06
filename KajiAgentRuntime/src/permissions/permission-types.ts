import type { AgentTool } from "@oh-my-pi/pi-agent-core";
import type { ApprovalMode } from "../tools/approval";
import type { ClientBridge } from "../session/client-bridge";

export type PermissionDecision = "allow" | "prompt" | "deny";
export type StoredPermissionDecision = "allow" | "deny";
export type PermissionDuration = "once" | "session" | "always";
export type PermissionCategory = "browser" | "host" | "mcp" | "web" | "runtime";
export type PermissionKey =
	| "read"
	| "edit"
	| "write"
	| "delete"
	| "move"
	| "bash"
	| "lsp"
	| "browser"
	| "web"
	| "task"
	| "skill"
	| `mcp:${string}`
	| `kaji:${string}`;

export interface PermissionRule {
	pattern: string;
	decision: PermissionDecision;
	duration?: PermissionDuration;
}

export interface PermissionStoredDecisionSnapshot {
	cacheKey: string;
	decision: StoredPermissionDecision;
	duration: Exclude<PermissionDuration, "once">;
	createdAt: string;
	updatedAt: string;
}

export interface PermissionServiceSnapshot {
	rules: PermissionRule[];
	sessionDecisionCount: number;
	persistentDecisionCount: number;
	gatedAcpTools: string[];
	requestCount: number;
	denyCount: number;
	requestCountByKey: Record<string, number>;
	denyCountByKey: Record<string, number>;
	requestCountByCategory: Record<PermissionCategory, number>;
	denyCountByCategory: Record<PermissionCategory, number>;
	sessionDecisions: PermissionStoredDecisionSnapshot[];
	persistentDecisions: PermissionStoredDecisionSnapshot[];
}

export interface PermissionRequest {
	key: PermissionKey;
	toolName: string;
	args?: unknown;
}

export interface AcpPermissionCall {
	bridge: ClientBridge;
	toolCallId: string;
	toolName: string;
	args: unknown;
	cwd: string;
	signal?: AbortSignal;
}

export interface RuntimePermissionCall {
	tool: Pick<AgentTool, "name" | "approval" | "formatApprovalDetails">;
	args: unknown;
	approvalMode: ApprovalMode;
	userPolicies?: Record<string, unknown>;
	hasUI: boolean;
	requestApproval: (prompt: string) => Promise<boolean>;
}

export function emptyPermissionServiceSnapshot(): PermissionServiceSnapshot {
	return {
		rules: [],
		sessionDecisionCount: 0,
		persistentDecisionCount: 0,
		gatedAcpTools: [],
		requestCount: 0,
		denyCount: 0,
		requestCountByKey: {},
		denyCountByKey: {},
		requestCountByCategory: {},
		denyCountByCategory: {},
		sessionDecisions: [],
		persistentDecisions: [],
	};
}
