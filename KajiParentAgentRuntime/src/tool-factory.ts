import type { AgentTool, AgentToolResult } from "@earendil-works/pi-agent-core";
import { Type } from "@earendil-works/pi-ai";
import { createID, type PendingTool, type RuntimeContext, send, stringifyResult } from "./protocol.js";

export type ToolSchema = ReturnType<typeof Type.Object>;

export function createKajiToolFactory(pendingTools: Map<string, PendingTool>) {
	function callKajiTool(name: string, args: Record<string, unknown>, context: RuntimeContext): Promise<unknown> {
		const id = createID("tool");
		const promise = new Promise<unknown>((resolve, reject) => pendingTools.set(id, { resolve, reject }));
		send({ type: "tool_call", id, taskID: context.taskID, name: kajiProtocolToolName(name), arguments: args });
		return promise;
	}

	return function tool(
		name: string,
		description: string,
		parameters: ToolSchema,
		context: RuntimeContext,
	): AgentTool {
		return {
			name,
			label: name,
			description,
			parameters,
			execute: async (_toolCallId, params, signal): Promise<AgentToolResult<unknown>> => {
				if (signal?.aborted) throw new Error("Tool call aborted");
				const result = await callKajiTool(name, params as Record<string, unknown>, context);
				return { content: [{ type: "text", text: stringifyResult(result) }], details: result };
			},
		};
	};
}

export function localTool(
	name: string,
	description: string,
	parameters: ToolSchema,
	execute: (params: Record<string, unknown>, signal?: AbortSignal) => Promise<unknown> | unknown,
): AgentTool {
	return {
		name,
		label: name,
		description,
		parameters,
		execute: async (_toolCallId, params, signal): Promise<AgentToolResult<unknown>> => {
			if (signal?.aborted) throw new Error("Tool call aborted");
			const result = await execute(params as Record<string, unknown>, signal);
			return { content: [{ type: "text", text: stringifyResult(result) }], details: result };
		},
	};
}

function kajiProtocolToolName(name: string) {
	if (name === "kaji_list_projects") return "kaji.list_projects";
	if (name === "kaji_get_active_context") return "kaji.get_active_context";
	if (name === "kaji_list_coding_agents") return "kaji.list_coding_agents";
	if (name === "kaji_ask_user") return "kaji.ask_user";
	if (name === "kaji_choose_agent") return "kaji.choose_agent";
	if (name === "kaji_subagent") return "kaji.subagent";
	if (name === "kaji_open_project") return "kaji.open_project";
	if (name === "kaji_select_project") return "kaji.select_project";
	if (name === "kaji_select_worktree") return "kaji.select_worktree";
	if (name === "kaji_open_terminal") return "kaji.open_terminal";
	if (name === "kaji_open_split") return "kaji.open_split";
	if (name === "kaji_jump_to_agent") return "kaji.jump_to_agent";
	if (name === "kaji_create_worktree") return "kaji.create_worktree";
	if (name === "kaji_get_changed_files") return "kaji.get_changed_files";
	if (name === "kaji_open_diff") return "kaji.open_diff";
	if (name === "kaji_run_verification") return "kaji.run_verification";
	return name;
}
