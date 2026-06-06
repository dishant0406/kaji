import { describe, expect, it } from "bun:test";
import {
	MAX_MCP_INSTRUCTIONS_LENGTH,
	appendMcpInstructionBlocks,
	truncateMcpInstructionMap,
	truncateMcpInstructions,
} from "../src/mcp-instructions";

describe("MCP instruction formatting", () => {
	it("truncates prompt blocks with a marker", () => {
		const text = "a".repeat(MAX_MCP_INSTRUCTIONS_LENGTH + 10);
		const truncated = truncateMcpInstructions(text);

		expect(truncated.length).toBe(MAX_MCP_INSTRUCTIONS_LENGTH + "\n[truncated]".length);
		expect(truncated.endsWith("\n[truncated]")).toBe(true);
	});

	it("appends server instructions to existing prompt", () => {
		const prompt = appendMcpInstructionBlocks("memory", new Map([["server", "use carefully"]]));

		expect(prompt).toContain("memory");
		expect(prompt).toContain("## MCP Server Instructions");
		expect(prompt).toContain("### server\nuse carefully");
	});

	it("truncates instruction maps without mutating the source", () => {
		const originalText = "b".repeat(MAX_MCP_INSTRUCTIONS_LENGTH + 5);
		const source = new Map([["server", originalText]]);
		const truncated = truncateMcpInstructionMap(source);

		expect(truncated?.get("server")?.length).toBe(MAX_MCP_INSTRUCTIONS_LENGTH);
		expect(source.get("server")).toBe(originalText);
	});
});
