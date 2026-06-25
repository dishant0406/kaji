import { getDefault, type SettingPath, type Settings, type SettingValue } from "../config/settings";

export type RuntimeProfileMode = "rpc" | "tui" | "acp" | "subagent";
export type RuntimeProfileID = "kaji-rpc-build" | "kaji-rpc-plan" | "kaji-rpc-explore" | "kaji-rpc-review" | "kaji-subagent-default" | "kaji-subagent-explore-lite";

export type RuntimePermissionMode = "read-allow" | "ask" | "auto";

export interface RuntimeRetryPolicy {
	enabled: boolean;
	maxRetries: number;
	baseDelayMs: number;
}

export interface RuntimeCompactionPolicy {
	enabled: boolean;
	strategy: "context-full" | "handoff" | "off";
	autoContinue: boolean;
}

export interface RuntimeSubagentPolicy {
	enabled: boolean;
	maxConcurrency: number;
	maxRecursionDepth: number;
	isolation: "none" | "auto" | "apfs" | "btrfs" | "zfs" | "reflink" | "overlayfs" | "projfs" | "block-clone" | "rcopy";
}

export interface RuntimeProfile {
	id: RuntimeProfileID;
	mode: RuntimeProfileMode;
	toolPatterns: readonly string[];
	hiddenToolPatterns: readonly string[];
	defaultSettingPaths: readonly SettingPath[];
	permissionMode: RuntimePermissionMode;
	retry: RuntimeRetryPolicy;
	compaction: RuntimeCompactionPolicy;
	subagents: RuntimeSubagentPolicy;
}

export const KAJI_RPC_DEFAULT_SETTING_PATHS = [
	"todo.enabled",
	"todo.reminders",
	"todo.reminders.max",
	"todo.eager",
	"async.enabled",
	"async.maxJobs",
	"bash.autoBackground.enabled",
	"bash.autoBackground.thresholdMs",
	"task.isolation.mode",
	"task.isolation.merge",
	"task.isolation.commits",
	"task.eager",
	"task.simple",
	"task.maxConcurrency",
	"task.maxRecursionDepth",
	"task.disabledAgents",
	"task.agentModelOverrides",
	"disabledProviders",
	"memory.backend",
	"memories.enabled",
] as const satisfies readonly SettingPath[];

function baseRpcProfile(): RuntimeProfile {
	return {
		id: "kaji-rpc-build",
		mode: "rpc",
		toolPatterns: ["read", "bash", "edit", "undo", "resolve", "task", "todo_write", "todo_read", "todo_verify", "find", "search", "lsp", "kaji_*", "runtime_profile_dump", "runtime_telemetry_dump", "tool_catalog_dump", "prompt_preview", "permission_rules_dump", "subagent_tree_dump"],
		hiddenToolPatterns: ["yield", "report_finding", "report_tool_issue", "goal"],
		defaultSettingPaths: KAJI_RPC_DEFAULT_SETTING_PATHS,
		permissionMode: "read-allow",
		retry: {
			enabled: Boolean(getDefault("retry.enabled")),
			maxRetries: Number(getDefault("retry.maxRetries")),
			baseDelayMs: Number(getDefault("retry.baseDelayMs")),
		},
		compaction: {
			enabled: Boolean(getDefault("compaction.enabled")),
			strategy: getDefault("compaction.strategy"),
			autoContinue: Boolean(getDefault("compaction.autoContinue")),
		},
		subagents: {
			enabled: Boolean(getDefault("task.eager")),
			maxConcurrency: Number(getDefault("task.maxConcurrency")),
			maxRecursionDepth: Number(getDefault("task.maxRecursionDepth")),
			isolation: getDefault("task.isolation.mode"),
		},
	};
}

export function kajiRpcRuntimeProfile(): RuntimeProfile {
	return baseRpcProfile();
}

export function kajiRpcPlanRuntimeProfile(): RuntimeProfile {
	return { ...baseRpcProfile(), id: "kaji-rpc-plan", toolPatterns: ["read", "find", "search", "lsp", "task", "todo_read", "todo_verify", "resolve"] };
}

export function kajiRpcExploreRuntimeProfile(): RuntimeProfile {
	return { ...baseRpcProfile(), id: "kaji-rpc-explore", toolPatterns: ["read", "find", "search", "lsp", "task", "todo_read", "todo_verify", "kaji_*"], permissionMode: "read-allow" };
}

export function kajiRpcReviewRuntimeProfile(): RuntimeProfile {
	return { ...baseRpcProfile(), id: "kaji-rpc-review", toolPatterns: ["read", "find", "search", "lsp", "bash", "todo_read", "todo_verify", "kaji_*"], permissionMode: "ask" };
}

export function kajiSubagentDefaultRuntimeProfile(): RuntimeProfile {
	return { ...baseRpcProfile(), id: "kaji-subagent-default", mode: "subagent", hiddenToolPatterns: ["yield", "report_finding"] };
}

export function kajiSubagentExploreLiteRuntimeProfile(): RuntimeProfile {
	return {
		...baseRpcProfile(),
		id: "kaji-subagent-explore-lite",
		mode: "subagent",
		toolPatterns: ["read", "find", "search", "ast_grep", "lsp", "todo_read", "todo_verify", "kaji_fff_*", "kaji_code_graph_*"],
		hiddenToolPatterns: ["yield", "report_finding"],
		permissionMode: "read-allow",
		subagents: { ...baseRpcProfile().subagents, maxRecursionDepth: 0 },
	};
}

export function runtimeProfiles(): RuntimeProfile[] {
	return [
		kajiRpcRuntimeProfile(),
		kajiRpcPlanRuntimeProfile(),
		kajiRpcExploreRuntimeProfile(),
		kajiRpcReviewRuntimeProfile(),
		kajiSubagentDefaultRuntimeProfile(),
		kajiSubagentExploreLiteRuntimeProfile(),
	];
}

export function getRuntimeProfile(id: RuntimeProfileID): RuntimeProfile {
	const profile = runtimeProfiles().find(candidate => candidate.id === id);
	if (!profile) throw new Error(`Unknown runtime profile: ${id}`);
	return profile;
}

export function applyRuntimeProfileDefaultSettings(targetSettings: Settings, profile: RuntimeProfile): void {
	const settingPaths = [...profile.defaultSettingPaths].sort((left, right) => {
		return right.split(".").length - left.split(".").length;
	});
	for (const settingPath of settingPaths) {
		targetSettings.override(settingPath, getDefault(settingPath) as SettingValue<typeof settingPath>);
	}
}
