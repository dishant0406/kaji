import type { AgentTool, AgentToolResult } from "@oh-my-pi/pi-agent-core";
import * as z from "zod/v4";
import type { ToolSession } from "../sdk";

const toolCatalogDumpSchema = z.object({}).describe("dump active and discoverable tool catalog state");

export interface ToolCatalogDumpDetails {
	activeTools: string[];
	allTools: string[];
	selectedDiscoveredTools: string[];
	discoverableTools: Array<{ name: string; source: string; summary?: string }>;
}

export class ToolCatalogDumpTool implements AgentTool<typeof toolCatalogDumpSchema, ToolCatalogDumpDetails> {
	readonly name = "tool_catalog_dump";
	readonly approval = "read" as const;
	readonly label = "Tool Catalog Dump";
	readonly summary = "Inspect active and discoverable Kaji tools";
	readonly description = "Dump active, registered, selected discovered, and discoverable tools for runtime debugging.";
	readonly parameters = toolCatalogDumpSchema;
	readonly strict = true;
	readonly loadMode = "discoverable";

	constructor(private readonly session: ToolSession) {}

	async execute(): Promise<AgentToolResult<ToolCatalogDumpDetails>> {
		const discoverableTools = (this.session.getDiscoverableTools?.() ?? []).map(tool => ({
			name: tool.name,
			source: tool.source,
			summary: tool.summary,
		}));
		const details = {
			activeTools: this.session.getActiveToolNames?.() ?? [],
			allTools: this.session.getAllToolNames?.() ?? [],
			selectedDiscoveredTools: this.session.getSelectedDiscoveredToolNames?.() ?? [],
			discoverableTools,
		};
		return { content: [{ type: "text", text: formatToolCatalogDump(details) }], details };
	}
}

function formatToolCatalogDump(details: ToolCatalogDumpDetails): string {
	return [
		`Active tools (${details.activeTools.length}): ${details.activeTools.join(", ") || "none"}`,
		`Registered tools (${details.allTools.length}): ${details.allTools.join(", ") || "none"}`,
		`Selected discovered tools (${details.selectedDiscoveredTools.length}): ${details.selectedDiscoveredTools.join(", ") || "none"}`,
		`Discoverable tools: ${details.discoverableTools.length}`,
	].join("\n");
}
