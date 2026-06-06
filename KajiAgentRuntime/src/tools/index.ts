import { $env, $flag, logger } from "@oh-my-pi/pi-utils";
import { checkPythonKernelAvailability } from "../eval/py/kernel";
import { MAIN_AGENT_ID } from "../registry/agent-registry";
import { wrapToolWithMetaNotice } from "./output-meta";
import { createReportToolIssueTool, isAutoQaEnabled } from "./report-tool-issue";
import { BUILTIN_TOOLS, HIDDEN_TOOLS, type Tool, type ToolFactory } from "./tool-catalog";
import { resolveToolNames } from "./tool-resolver";
import type { ToolSession } from "./tool-session";

export * from "../edit";
export * from "../exa";
export type * from "../exa/types";
export * from "../goals";
export * from "../lsp";
export * from "../session/streaming-output";
export * from "../task";
export * from "../web/search";
export * from "./ask";
export * from "./ast-edit";
export * from "./ast-grep";
export * from "./bash";
export * from "./browser";
export * from "./checkpoint";
export * from "./debug";
export * from "./edit-safety";
export * from "./eval";
export * from "./find";
export * from "./gh";
export * from "./hindsight-recall";
export * from "./hindsight-reflect";
export * from "./hindsight-retain";
export * from "./image-gen";
export * from "./inspect-image";
export * from "./irc";
export * from "./job";
export * from "./permission-rules-dump";
export * from "./prompt-preview";
export * from "./read";
export * from "./recipe";
export * from "./render-mermaid";
export * from "./runtime-profile-dump";
export * from "./runtime-telemetry-dump";
export * from "./report-tool-issue";
export * from "./resolve";
export * from "./review";
export * from "./search";
export * from "./search-tool-bm25";
export * from "./ssh";
export * from "./subagent-tree-dump";
export * from "./tool-catalog";
export * from "./tool-catalog-dump";
export * from "./tool-resolver";
export * from "./todo-read";
export * from "./todo-verify";
export * from "./todo-write";
export * from "./tts";
export * from "./undo";
export * from "./write";
export * from "./yield";

export type { ContextFileEntry, ToolSession } from "./tool-session";
export type {
	DiscoverableTool,
	DiscoverableToolSearchIndex,
	DiscoverableToolSearchResult,
	DiscoverableToolSource,
} from "../tool-discovery/tool-index";

export interface EvalBackendsAllowance {
	python: boolean;
	js: boolean;
}

function getEvalBackendsFromEnv(): EvalBackendsAllowance | null {
	const pyEnv = $env.PI_PY;
	const jsEnv = $env.PI_JS;
	if (pyEnv === undefined && jsEnv === undefined) return null;
	return { python: pyEnv === undefined ? true : $flag("PI_PY"), js: jsEnv === undefined ? true : $flag("PI_JS") };
}

export function readEvalBackendsAllowance(session: ToolSession): EvalBackendsAllowance {
	return { python: session.settings.get("eval.py") ?? true, js: session.settings.get("eval.js") ?? true };
}

export function resolveEvalBackends(session: ToolSession): EvalBackendsAllowance {
	return getEvalBackendsFromEnv() ?? readEvalBackendsAllowance(session);
}

export async function createTools(session: ToolSession, toolNames?: string[]): Promise<Tool[]> {
	const includeYield = session.requireYieldTool === true;
	const enableLsp = session.enableLsp ?? true;
	let requestedTools = toolNames && toolNames.length > 0 ? [...new Set(toolNames.map(name => name.toLowerCase()))] : undefined;
	const goalEnabled = session.settings.get("goal.enabled");
	const goalModeActive = goalEnabled && session.getGoalModeState?.()?.enabled === true;
	if (goalModeActive && requestedTools && !requestedTools.includes("goal")) requestedTools = [...requestedTools, "goal"];
	const backends = resolveEvalBackends(session);
	const allowPython = backends.python;
	const allowJs = backends.js;
	const skipPythonPreflight = session.skipPythonPreflight === true;
	let pythonAvailable = true;
	if (!skipPythonPreflight && allowPython && !allowJs && (requestedTools === undefined || requestedTools.includes("eval"))) {
		const availability = await logger.time("createTools:pythonCheck", checkPythonKernelAvailability, session.cwd);
		pythonAvailable = availability.ok;
		if (!availability.ok) logger.warn("Python kernel unavailable and JS backend disabled; eval will be unavailable", { reason: availability.reason });
	}

	const effectivePythonAllowed = allowPython && pythonAvailable;
	const allowEval = effectivePythonAllowed || allowJs;
	if (requestedTools) expandRequestedTools(session, requestedTools);
	const effectiveDiscoveryMode = resolveEffectiveDiscoveryMode(session);
	const discoveryActive = effectiveDiscoveryMode !== "off";
	const allTools: Record<string, ToolFactory> = { ...BUILTIN_TOOLS, ...HIDDEN_TOOLS };
	const isToolAllowed = (name: string) => {
		if (name === "goal") return goalEnabled && goalModeActive;
		if (name === "lsp") return enableLsp && session.settings.get("lsp.enabled");
		if (name === "bash") return true;
		if (name === "eval") return allowEval;
		if (name === "debug") return session.settings.get("debug.enabled");
		if (name === "todo_write" || name === "todo_read" || name === "todo_verify") return !includeYield && session.settings.get("todo.enabled");
		if (isRuntimeDebugTool(name)) return session.settings.get("debug.enabled");
		if (name === "find") return session.settings.get("find.enabled");
		if (name === "search") return session.settings.get("search.enabled");
		if (name === "github") return session.settings.get("github.enabled");
		if (name === "ast_grep") return session.settings.get("astGrep.enabled");
		if (name === "ast_edit") return session.settings.get("astEdit.enabled");
		if (name === "render_mermaid") return session.settings.get("renderMermaid.enabled");
		if (name === "inspect_image") return session.settings.get("inspect_image.enabled");
		if (name === "web_search") return session.settings.get("web_search.enabled");
		if (name === "search_tool_bm25") return discoveryActive;
		if (name === "browser") return session.settings.get("browser.enabled");
		if (name === "checkpoint" || name === "rewind") return session.settings.get("checkpoint.enabled");
		if (name === "irc") return isIrcAllowed(session);
		if (name === "recipe") return session.settings.get("recipe.enabled");
		if (name === "retain" || name === "recall" || name === "reflect") return session.settings.get("memory.backend") === "hindsight";
		if (name === "task") return isTaskAllowed(session);
		return true;
	};
	if (includeYield && requestedTools && !requestedTools.includes("yield")) requestedTools.push("yield");
	const filteredRequestedTools = requestedTools
		? resolveToolNames(Object.keys(allTools), requestedTools).entries.map(entry => entry.name).filter(name => isToolAllowed(name))
		: undefined;
	const baseEntries = filteredRequestedTools !== undefined
		? filteredRequestedTools.filter(name => name !== "resolve").map(name => [name, allTools[name]] as const)
		: [
				...Object.entries(BUILTIN_TOOLS).filter(([name]) => isToolAllowed(name)).map(([name, factory]) => [name, factory] as const),
				...(includeYield ? ([ ["yield", HIDDEN_TOOLS.yield] ] as const) : []),
				...(goalModeActive ? ([ ["goal", HIDDEN_TOOLS.goal] ] as const) : []),
			];
	const baseResults = await Promise.all(baseEntries.map(async ([name, factory]) => {
		const tool = await logger.time(`createTools:${name}`, factory as ToolFactory, session);
		return tool ? wrapToolWithMetaNotice(tool) : null;
	}));
	const tools = baseResults.filter((r): r is Tool => r !== null);
	if (!tools.some(tool => tool.name === "resolve")) {
		const resolveTool = await logger.time("createTools:resolve", HIDDEN_TOOLS.resolve, session);
		if (resolveTool) tools.push(wrapToolWithMetaNotice(resolveTool));
	}
	const autoQA = isAutoQaEnabled(session.settings);
	if (autoQA && !tools.some(t => t.name === "report_tool_issue")) {
		const activeBuiltinNames = tools.map(t => t.name).filter(name => (name in BUILTIN_TOOLS || name in HIDDEN_TOOLS) && name !== "report_tool_issue");
		const qaTool = createReportToolIssueTool(session, activeBuiltinNames);
		if (qaTool) tools.push(wrapToolWithMetaNotice(qaTool));
	}
	return tools;
}

function expandRequestedTools(session: ToolSession, requestedTools: string[]): void {
	if (requestedTools.includes("search") && !requestedTools.includes("ast_grep") && session.settings.get("astGrep.enabled")) requestedTools.push("ast_grep");
	if (requestedTools.includes("edit") && !requestedTools.includes("ast_edit") && session.settings.get("astEdit.enabled")) requestedTools.push("ast_edit");
	if (requestedTools.includes("bash") && !requestedTools.includes("recipe") && session.settings.get("recipe.enabled")) requestedTools.push("recipe");
	if (session.settings.get("memory.backend") !== "hindsight") return;
	for (const name of ["recall", "retain", "reflect"]) {
		if (!requestedTools.includes(name)) requestedTools.push(name);
	}
}

function resolveEffectiveDiscoveryMode(session: ToolSession): "off" | "mcp-only" | "all" {
	const toolsDiscoveryMode = session.settings.get("tools.discoveryMode");
	if (toolsDiscoveryMode !== "off") return toolsDiscoveryMode as "off" | "mcp-only" | "all";
	return session.settings.get("mcp.discoveryMode") ? "mcp-only" : "off";
}

function isRuntimeDebugTool(name: string): boolean {
	return name === "runtime_profile_dump" || name === "runtime_telemetry_dump" || name === "tool_catalog_dump" || name === "prompt_preview" || name === "permission_rules_dump" || name === "subagent_tree_dump";
}

function isIrcAllowed(session: ToolSession): boolean {
	if (!session.settings.get("irc.enabled")) return false;
	if (!session.settings.get("async.enabled") && session.getAgentId?.() === MAIN_AGENT_ID) return false;
	return true;
}

function isTaskAllowed(session: ToolSession): boolean {
	const maxDepth = session.settings.get("task.maxRecursionDepth") ?? 2;
	const currentDepth = session.taskDepth ?? 0;
	return maxDepth < 0 || currentDepth < maxDepth;
}
