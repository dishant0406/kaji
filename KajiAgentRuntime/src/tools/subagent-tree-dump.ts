import type { AgentTool, AgentToolResult } from "@oh-my-pi/pi-agent-core";
import * as z from "zod/v4";
import type { AgentRef } from "../registry/agent-registry";
import type { ToolSession } from "../sdk";

const subagentTreeDumpSchema = z.object({}).describe("dump registered main and subagent sessions");

export interface SubagentTreeDumpDetails {
	agents: Array<{
		id: string;
		displayName: string;
		kind: AgentRef["kind"];
		parentId?: string;
		status: AgentRef["status"];
		sessionFile: string | null;
	}>;
}

export class SubagentTreeDumpTool implements AgentTool<typeof subagentTreeDumpSchema, SubagentTreeDumpDetails> {
	readonly name = "subagent_tree_dump";
	readonly approval = "read" as const;
	readonly label = "Subagent Tree Dump";
	readonly summary = "Inspect live agent and subagent tree";
	readonly description = "Dump registered main and subagent sessions for runtime debugging.";
	readonly parameters = subagentTreeDumpSchema;
	readonly strict = true;
	readonly loadMode = "discoverable";

	constructor(private readonly session: ToolSession) {}

	async execute(): Promise<AgentToolResult<SubagentTreeDumpDetails>> {
		const agents = (this.session.agentRegistry?.list() ?? []).map(ref => ({
			id: ref.id,
			displayName: ref.displayName,
			kind: ref.kind,
			...(ref.parentId ? { parentId: ref.parentId } : {}),
			status: ref.status,
			sessionFile: ref.sessionFile,
		}));
		const details = { agents };
		return { content: [{ type: "text", text: formatSubagentTreeDump(details) }], details };
	}
}

function formatSubagentTreeDump(details: SubagentTreeDumpDetails): string {
	if (details.agents.length === 0) return "Registered agents: none";
	return details.agents
		.map(agent => `${agent.id} [${agent.kind}/${agent.status}]${agent.parentId ? ` parent=${agent.parentId}` : ""}`)
		.join("\n");
}
