import type { AgentTool } from "@oh-my-pi/pi-agent-core";
import type { Settings } from "../config/settings";
import { EditTool } from "../edit";
import { GoalTool } from "../goals/tools/goal-tool";
import { LspTool } from "../lsp";
import { TaskTool } from "../task";
import { WebSearchTool } from "../web/search";
import { AskTool } from "./ask";
import { AstEditTool } from "./ast-edit";
import { AstGrepTool } from "./ast-grep";
import { BashTool } from "./bash";
import { CheckpointTool, RewindTool } from "./checkpoint";
import { DebugTool } from "./debug";
import { EvalTool } from "./eval";
import { FindTool } from "./find";
import { GithubTool } from "./gh";
import { HindsightRecallTool } from "./hindsight-recall";
import { HindsightReflectTool } from "./hindsight-reflect";
import { HindsightRetainTool } from "./hindsight-retain";
import { InspectImageTool } from "./inspect-image";
import { IrcTool } from "./irc";
import { JobTool } from "./job";
import { PermissionRulesDumpTool } from "./permission-rules-dump";
import { PromptPreviewTool } from "./prompt-preview";
import { ReadTool } from "./read";
import { RecipeTool } from "./recipe";
import { RenderMermaidTool } from "./render-mermaid";
import { createReportToolIssueTool } from "./report-tool-issue";
import { ResolveTool } from "./resolve";
import { reportFindingTool } from "./review";
import { RuntimeProfileDumpTool } from "./runtime-profile-dump";
import { RuntimeTelemetryDumpTool } from "./runtime-telemetry-dump";
import { SearchTool } from "./search";
import { SearchToolBm25Tool } from "./search-tool-bm25";
import { loadSshTool } from "./ssh";
import { SubagentTreeDumpTool } from "./subagent-tree-dump";
import { TodoReadTool } from "./todo-read";
import { TodoVerifyTool } from "./todo-verify";
import { TodoWriteTool } from "./todo-write";
import { ToolCatalogDumpTool } from "./tool-catalog-dump";
import type { ToolSession } from "./tool-session";
import { UndoTool } from "./undo";
import { WriteTool } from "./write";
import { YieldTool } from "./yield";

export type Tool = AgentTool<any, any, any>;
export type ToolFactory = (session: ToolSession) => Tool | null | Promise<Tool | null>;

export type BuiltinToolLoadMode = "essential" | "discoverable";

/** Default essential tool names when tools.essentialOverride is empty. */
export const DEFAULT_ESSENTIAL_TOOL_NAMES: readonly string[] = ["read", "bash", "edit"] as const;

/**
 * Resolve the active essential built-in tool names from settings.
 * Returns `tools.essentialOverride` if non-empty (filtered to known built-ins),
 * otherwise `DEFAULT_ESSENTIAL_TOOL_NAMES`.
 */
export function computeEssentialBuiltinNames(settings: Settings): string[] {
	const override = settings.get("tools.essentialOverride") ?? [];
	const cleaned = override.map(name => name.trim()).filter(Boolean);
	if (cleaned.length > 0) {
		return cleaned.filter(name => name in BUILTIN_TOOLS);
	}
	return [...DEFAULT_ESSENTIAL_TOOL_NAMES];
}

/**
 * Public callable factory map. External callers may invoke `BUILTIN_TOOLS.read(session)` or
 * `BUILTIN_TOOLS[name](session)` to construct a tool directly.
 */
export const BUILTIN_TOOLS: Record<string, ToolFactory> = {
	read: s => new ReadTool(s),
	bash: s => new BashTool(s),
	edit: s => new EditTool(s),
	ast_grep: s => new AstGrepTool(s),
	ast_edit: s => new AstEditTool(s),
	render_mermaid: s => new RenderMermaidTool(s),
	ask: AskTool.createIf,
	debug: DebugTool.createIf,
	eval: s => new EvalTool(s),
	ssh: loadSshTool,
	github: GithubTool.createIf,
	find: s => new FindTool(s),
	search: s => new SearchTool(s),
	lsp: LspTool.createIf,
	inspect_image: s => new InspectImageTool(s),
	checkpoint: CheckpointTool.createIf,
	rewind: RewindTool.createIf,
	task: s => TaskTool.create(s),
	job: JobTool.createIf,
	recipe: RecipeTool.createIf,
	irc: IrcTool.createIf,
	todo_write: s => new TodoWriteTool(s),
	todo_read: s => new TodoReadTool(s),
	todo_verify: s => new TodoVerifyTool(s),
	web_search: s => new WebSearchTool(s),
	search_tool_bm25: SearchToolBm25Tool.createIf,
	runtime_profile_dump: s => new RuntimeProfileDumpTool(s),
	runtime_telemetry_dump: s => new RuntimeTelemetryDumpTool(s),
	tool_catalog_dump: s => new ToolCatalogDumpTool(s),
	prompt_preview: s => new PromptPreviewTool(s),
	permission_rules_dump: s => new PermissionRulesDumpTool(s),
	subagent_tree_dump: s => new SubagentTreeDumpTool(s),
	undo: s => new UndoTool(s),
	write: s => new WriteTool(s),
	retain: HindsightRetainTool.createIf,
	recall: HindsightRecallTool.createIf,
	reflect: HindsightReflectTool.createIf,
};

export const HIDDEN_TOOLS: Record<string, ToolFactory> = {
	yield: s => new YieldTool(s),
	report_finding: () => reportFindingTool,
	report_tool_issue: s => createReportToolIssueTool(s),
	resolve: s => new ResolveTool(s),
	goal: s => new GoalTool(s),
};

export type ToolName = keyof typeof BUILTIN_TOOLS;
