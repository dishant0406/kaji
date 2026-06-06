import type { AgentTool, AgentToolResult } from "@oh-my-pi/pi-agent-core";
import * as z from "zod/v4";
import type { ToolSession } from "../sdk";

const promptPreviewSchema = z
	.object({
		include_blocks: z.boolean().optional().describe("Include full prompt blocks in details"),
	})
	.describe("inspect active system prompt blocks");

export interface PromptPreviewDetails {
	blockCount: number;
	characterCount: number;
	blocks?: string[];
}

export class PromptPreviewTool implements AgentTool<typeof promptPreviewSchema, PromptPreviewDetails> {
	readonly name = "prompt_preview";
	readonly approval = "read" as const;
	readonly label = "Prompt Preview";
	readonly summary = "Inspect active system prompt composition";
	readonly description = "Preview the active provider-facing system prompt blocks for runtime debugging.";
	readonly parameters = promptPreviewSchema;
	readonly strict = true;
	readonly loadMode = "discoverable";

	constructor(private readonly session: ToolSession) {}

	async execute(_toolCallId: string, params: z.infer<typeof promptPreviewSchema>): Promise<AgentToolResult<PromptPreviewDetails>> {
		const blocks = this.session.getSystemPrompt?.() ?? [];
		const details: PromptPreviewDetails = {
			blockCount: blocks.length,
			characterCount: blocks.reduce((sum, block) => sum + block.length, 0),
			...(params.include_blocks === true ? { blocks } : {}),
		};
		return { content: [{ type: "text", text: formatPromptPreview(details) }], details };
	}
}

function formatPromptPreview(details: PromptPreviewDetails): string {
	return [`System prompt blocks: ${details.blockCount}`, `Characters: ${details.characterCount}`].join("\n");
}
