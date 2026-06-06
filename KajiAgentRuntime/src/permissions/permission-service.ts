import type { ClientBridgePermissionOption, ClientBridgePermissionOutcome } from "../session/client-bridge";
import { formatApprovalPrompt, requiresApproval, resolveApproval } from "../tools/approval";
import { ToolAbortError, ToolError } from "../tools/tool-errors";
import { PermissionStats } from "./permission-stats";
import { matchPermissionPattern } from "./permission-pattern";
import { commandContent, extractPermissionLocations, getPermissionIntent, type PermissionIntent } from "./permission-intent";
import type { PermissionDecisionPersistence } from "./permission-decision-store";
import type {
	AcpPermissionCall,
	PermissionDecision,
	PermissionKey,
	PermissionRequest,
	PermissionRule,
	PermissionServiceSnapshot,
	PermissionStoredDecisionSnapshot,
	RuntimePermissionCall,
	StoredPermissionDecision,
} from "./permission-types";

export type {
	AcpPermissionCall,
	PermissionDecision,
	PermissionDuration,
	PermissionKey,
	PermissionRequest,
	PermissionRule,
	PermissionServiceSnapshot,
	PermissionStoredDecisionSnapshot,
	RuntimePermissionCall,
	StoredPermissionDecision,
} from "./permission-types";

const ACP_GATED_TOOLS = new Set(["bash", "edit", "delete", "move"]);
const PERMISSION_OPTIONS: ClientBridgePermissionOption[] = [
	{ optionId: "allow_once", name: "Allow once", kind: "allow_once" },
	{ optionId: "allow_always", name: "Always allow", kind: "allow_always" },
	{ optionId: "reject_once", name: "Reject", kind: "reject_once" },
	{ optionId: "reject_always", name: "Always reject", kind: "reject_always" },
];
const PERMISSION_OPTIONS_BY_ID = new Map(PERMISSION_OPTIONS.map(option => [option.optionId, option]));

export class PermissionService {
	#rules: PermissionRule[] = [];
	#sessionDecisions = new Map<string, PermissionStoredDecisionSnapshot>();
	#persistentDecisions = new Map<string, PermissionStoredDecisionSnapshot>();
	#persistence?: PermissionDecisionPersistence;
	#stats = new PermissionStats();

	constructor(persistence?: PermissionDecisionPersistence) {
		if (persistence) this.setPersistentDecisionPersistence(persistence);
	}

	setPersistentDecisionPersistence(persistence: PermissionDecisionPersistence): void {
		this.#persistence = persistence;
		this.#persistentDecisions = toDecisionMap(persistence.load());
	}

	setRules(rules: PermissionRule[]): void {
		this.#rules = [...rules];
	}

	clearSessionDecisions(): void {
		this.#sessionDecisions.clear();
	}

	snapshot(): PermissionServiceSnapshot {
		return {
			rules: [...this.#rules],
			sessionDecisionCount: this.#sessionDecisions.size,
			persistentDecisionCount: this.#persistentDecisions.size,
			gatedAcpTools: [...ACP_GATED_TOOLS].sort(),
			sessionDecisions: [...this.#sessionDecisions.values()],
			persistentDecisions: [...this.#persistentDecisions.values()],
			...this.#stats.snapshot(),
		};
	}

	resolve(request: PermissionRequest): PermissionDecision {
		const cached = this.#getDecision(request.key);
		if (cached) return cached.decision;
		const match = [...this.#rules].reverse().find(rule => matchPermissionPattern(rule.pattern, request.key));
		return match?.decision ?? "prompt";
	}

	async authorizeRuntimeToolCall(call: RuntimePermissionCall): Promise<void> {
		const key = permissionKeyForTool(call.tool.name);
		const serviceDecision = this.resolve({ key, toolName: call.tool.name, args: call.args });
		if (serviceDecision === "deny") return this.#deny(key, `Tool "${call.tool.name}" is blocked by permission policy.`);
		if (serviceDecision === "allow") return;
		const approval = resolveApproval(call.tool, call.args, call.approvalMode, call.userPolicies ?? {});
		if (approval.policy === "deny") return this.#deny(key, permissionPolicyMessage(call.tool.name));
		const approvalCheck = requiresApproval(call.tool, call.args, call.approvalMode, call.userPolicies ?? {});
		if (!approvalCheck.required) return;
		if (!call.hasUI) return this.#deny(key, noUiMessage(call.tool.name));
		this.#stats.recordRequest(key);
		const approved = await call.requestApproval(formatApprovalPrompt(call.tool, call.args, approvalCheck.reason));
		if (!approved) return this.#deny(key, `Tool call denied by user: ${call.tool.name}`);
	}

	shouldGateAcpTool(toolName: string): boolean {
		return ACP_GATED_TOOLS.has(toolName);
	}

	async authorizeAcpToolCall(call: AcpPermissionCall): Promise<void> {
		const intent = getPermissionIntent(call.toolName, call.args);
		if (!intent) return;
		const key = permissionKeyForTool(call.toolName);
		const cached = this.#getDecision(intent.cacheKey);
		if (cached?.decision === "allow") return;
		if (cached?.decision === "deny") return this.#deny(key, "Tool call rejected by user (preference)");
		if (call.signal?.aborted) throw new ToolAbortError("Permission request cancelled");
		this.#stats.recordRequest(key);
		const outcome = await this.#requestAcpPermission(call, intent);
		if (outcome.outcome === "cancelled") throw new ToolAbortError("Permission request cancelled");
		const selectedOption = PERMISSION_OPTIONS_BY_ID.get(outcome.optionId);
		if (!selectedOption) throw new ToolError(`Tool permission response used unknown option ID: ${outcome.optionId}`);
		if (selectedOption.kind === "allow_always") await this.#remember(intent.cacheKey, "allow", "always");
		if (selectedOption.kind === "reject_always") await this.#remember(intent.cacheKey, "deny", "always");
		if (selectedOption.kind === "reject_once" || selectedOption.kind === "reject_always") {
			return this.#deny(key, `Tool call rejected by user (${call.toolName})`);
		}
	}

	async #requestAcpPermission(call: AcpPermissionCall, intent: PermissionIntent): Promise<ClientBridgePermissionOutcome> {
		type PermissionRaceResult = { kind: "permission"; outcome: ClientBridgePermissionOutcome } | { kind: "aborted" };
		const { promise: abortPromise, resolve: resolveAbort } = Promise.withResolvers<PermissionRaceResult>();
		const onAbort = () => resolveAbort({ kind: "aborted" });
		call.signal?.addEventListener("abort", onAbort, { once: true });
		try {
			const permissionPromise = call.bridge.requestPermission!(
				{
					toolCallId: call.toolCallId,
					toolName: call.toolName,
					title: intent.title,
					...(call.toolName === "bash" ? { kind: "execute" as const } : {}),
					status: "pending",
					rawInput: call.args,
					...commandContent(call.toolName, call.args),
					locations: extractPermissionLocations(call.args, call.cwd, intent.paths),
				},
				PERMISSION_OPTIONS,
				call.signal,
			).then(outcome => ({ kind: "permission" as const, outcome }));
			const raced = await Promise.race([permissionPromise, abortPromise]);
			if (raced.kind === "aborted" || call.signal?.aborted) throw new ToolAbortError("Permission request cancelled");
			return raced.outcome;
		} finally {
			call.signal?.removeEventListener("abort", onAbort);
		}
	}

	#getDecision(cacheKey: string): PermissionStoredDecisionSnapshot | undefined {
		return this.#sessionDecisions.get(cacheKey) ?? this.#persistentDecisions.get(cacheKey);
	}

	async #remember(cacheKey: string, decision: StoredPermissionDecision, duration: "session" | "always"): Promise<void> {
		const previous = this.#getDecision(cacheKey);
		const now = new Date().toISOString();
		const stored = { cacheKey, decision, duration, createdAt: previous?.createdAt ?? now, updatedAt: now };
		const target = duration === "session" ? this.#sessionDecisions : this.#persistentDecisions;
		target.set(cacheKey, stored);
		if (duration === "always") await this.#persistence?.save(stored);
	}

	#deny(key: PermissionKey, message: string): never {
		this.#stats.recordDeny(key);
		throw new ToolError(message);
	}
}

export function permissionKeyForTool(toolName: string): PermissionKey {
	if (toolName.startsWith("mcp__")) return `mcp:${toolName}`;
	if (toolName.startsWith("kaji_")) return `kaji:${toolName}`;
	if (toolName === "edit" || toolName === "ast_edit") return "edit";
	if (toolName === "write" || toolName === "undo") return "write";
	if (toolName === "bash" || toolName === "eval" || toolName === "ssh") return "bash";
	if (toolName === "browser") return "browser";
	if (toolName === "web_search") return "web";
	if (toolName === "task" || toolName === "job") return "task";
	if (toolName === "lsp") return "lsp";
	return "read";
}

function toDecisionMap(decisions: PermissionStoredDecisionSnapshot[]): Map<string, PermissionStoredDecisionSnapshot> {
	return new Map(decisions.map(decision => [decision.cacheKey, decision]));
}

function permissionPolicyMessage(toolName: string): string {
	return `Tool "${toolName}" is blocked by user policy.\nTo allow: remove "tools.approval.${toolName}: deny" from config.`;
}

function noUiMessage(toolName: string): string {
	return `Tool "${toolName}" requires approval but no interactive UI available.\nOptions:\n  1. Set tools.approvalMode: yolo in /settings\n  2. Add tools.approval.${toolName}: allow to config\n  3. Use an interactive UI to approve the tool call`;
}
