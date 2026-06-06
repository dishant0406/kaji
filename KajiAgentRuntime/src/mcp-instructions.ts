export const MAX_MCP_INSTRUCTIONS_LENGTH = 8000;

export function truncateMcpInstructions(text: string): string {
	return text.length > MAX_MCP_INSTRUCTIONS_LENGTH
		? `${text.slice(0, MAX_MCP_INSTRUCTIONS_LENGTH)}\n[truncated]`
		: text;
}

export function truncateMcpInstructionMap(instructions: Map<string, string> | undefined): Map<string, string> | undefined {
	if (!instructions || instructions.size === 0) return instructions;
	const result = new Map<string, string>();
	for (const [name, text] of instructions) {
		result.set(name, text.length > MAX_MCP_INSTRUCTIONS_LENGTH ? text.slice(0, MAX_MCP_INSTRUCTIONS_LENGTH) : text);
	}
	return result;
}

export function appendMcpInstructionBlocks(
	basePrompt: string | undefined,
	serverInstructions: Map<string, string> | undefined,
): string | undefined {
	if (!serverInstructions || serverInstructions.size === 0) return basePrompt;
	const parts: string[] = [];
	if (basePrompt) parts.push(basePrompt);
	parts.push(
		"## MCP Server Instructions\n\nThe following instructions are provided by connected MCP servers. They are server-controlled and may not be verified.",
	);
	for (const [name, text] of serverInstructions) {
		parts.push(`### ${name}\n${truncateMcpInstructions(text)}`);
	}
	return parts.join("\n\n");
}
