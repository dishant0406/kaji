import type { AgentTool } from "@earendil-works/pi-agent-core";
import { Type } from "@earendil-works/pi-ai";
import type { PendingTool, RuntimeContext } from "./protocol.js";
import { createKajiToolFactory } from "./tool-factory.js";

export function kajiTools(context: RuntimeContext, pendingTools: Map<string, PendingTool>): AgentTool[] {
	const tool = createKajiToolFactory(pendingTools);
	return [
		tool("kaji_list_projects", "List projects available in Kaji.", Type.Object({}), context),
		tool(
			"kaji_get_active_context",
			"Get Kaji's active project, worktrees, and workspace context.",
			Type.Object({}),
			context,
		),
		tool(
			"kaji_list_coding_agents",
			"List enabled and installed coding agents with available model choices. Use this before planning delegation.",
			Type.Object({}),
			context,
		),
		tool(
			"kaji_ask_user",
			"Ask the user one concise question when required information is missing.",
			Type.Object({ question: Type.String() }),
			context,
		),
		tool(
			"kaji_choose_agent",
			"Ask the user whether to continue an existing child run or choose a coding agent/model for one specific task/project. Call once per independent task before spawning.",
			Type.Object({ task: Type.String(), project: Type.Optional(Type.String()) }),
			context,
		),
		tool(
			"kaji_subagent",
			"Manage Kaji subagent assignments. Use spawn for new work, replace for incomplete/stale work, send for continuing an assignment, status/result/wait for supervision, and stop to interrupt. Status/result/wait include terminalOutput when Kaji can read the child terminal screen.",
			Type.Object({
				action: Type.String(),
				assignmentID: Type.Optional(Type.String()),
				title: Type.Optional(Type.String()),
				prompt: Type.Optional(Type.String()),
				project: Type.Optional(Type.String()),
				provider: Type.Optional(Type.String()),
				model: Type.Optional(Type.String()),
				isolation: Type.Optional(Type.String()),
				timeoutSeconds: Type.Optional(Type.String()),
			}),
			context,
		),
		tool(
			"kaji_open_project",
			"Open and select a Kaji project by id, name, or path.",
			Type.Object({ project: Type.Optional(Type.String()), worktree: Type.Optional(Type.String()) }),
			context,
		),
		tool(
			"kaji_select_project",
			"Select a Kaji project by id, name, or path without spawning an agent.",
			Type.Object({ project: Type.Optional(Type.String()), worktree: Type.Optional(Type.String()) }),
			context,
		),
		tool(
			"kaji_select_worktree",
			"Select a worktree by id, name, path, or branch for the active or named project.",
			Type.Object({ project: Type.Optional(Type.String()), worktree: Type.Optional(Type.String()) }),
			context,
		),
		tool(
			"kaji_open_terminal",
			"Open a native Kaji terminal tab. Optional command runs in the selected project/worktree.",
			Type.Object({
				project: Type.Optional(Type.String()),
				worktree: Type.Optional(Type.String()),
				title: Type.Optional(Type.String()),
				command: Type.Optional(Type.String()),
			}),
			context,
		),
		tool(
			"kaji_open_split",
			"Open a native Kaji split. Optional command runs in the selected project/worktree. Direction may be horizontal or vertical for empty splits.",
			Type.Object({
				project: Type.Optional(Type.String()),
				worktree: Type.Optional(Type.String()),
				title: Type.Optional(Type.String()),
				command: Type.Optional(Type.String()),
				direction: Type.Optional(Type.String()),
			}),
			context,
		),
		tool("kaji_jump_to_agent", "Navigate Kaji to a child agent run by runID.", Type.Object({ runID: Type.String() }), context),
		tool(
			"kaji_create_worktree",
			"Create and select an isolated Git worktree for a project. By default creates a new branch; pass createBranch false to use an existing branch.",
			Type.Object({
				project: Type.Optional(Type.String()),
				name: Type.String(),
				branch: Type.Optional(Type.String()),
				createBranch: Type.Optional(Type.String()),
			}),
			context,
		),
		tool(
			"kaji_get_changed_files",
			"Get changed files for a runID or selected project/worktree. If runID is provided, Kaji attaches the snapshot to that run.",
			Type.Object({
				runID: Type.Optional(Type.String()),
				project: Type.Optional(Type.String()),
				worktree: Type.Optional(Type.String()),
			}),
			context,
		),
		tool(
			"kaji_open_diff",
			"Open Kaji's native diff viewer for a file. Prefer passing runID plus path when reviewing child-agent output.",
			Type.Object({
				runID: Type.Optional(Type.String()),
				project: Type.Optional(Type.String()),
				worktree: Type.Optional(Type.String()),
				path: Type.Optional(Type.String()),
				staged: Type.Optional(Type.String()),
			}),
			context,
		),
		tool(
			"kaji_run_verification",
			"Run the configured verification command for a tracked child agent run.",
			Type.Object({ runID: Type.String() }),
			context,
		),
	];
}
