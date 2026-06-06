import { describe, expect, test } from "bun:test";
import { Settings } from "../config/settings";
import { emptyPermissionServiceSnapshot } from "../permissions";
import { createTools } from ".";
import { PermissionRulesDumpTool } from "./permission-rules-dump";
import { PromptPreviewTool } from "./prompt-preview";
import { RuntimeProfileDumpTool } from "./runtime-profile-dump";
import { RuntimeTelemetryDumpTool } from "./runtime-telemetry-dump";
import { SubagentTreeDumpTool } from "./subagent-tree-dump";
import { ToolCatalogDumpTool } from "./tool-catalog-dump";

describe("runtime debug tools", () => {
	test("runtime_profile_dump reports runtime and model profiles", async () => {
		const tool = new RuntimeProfileDumpTool({ getActiveModelString: () => "gemini-2.5-pro" } as never);
		const result = await tool.execute("profile", { profile_id: "kaji-rpc-build" });

		expect(result.details?.profile.id).toBe("kaji-rpc-build");
		expect(result.details?.modelHarnessProfile.preferredEditTool).toBe("patch");
	});

	test("tool_catalog_dump reports active and discoverable tools", async () => {
		const tool = new ToolCatalogDumpTool({
			getActiveToolNames: () => ["read"],
			getAllToolNames: () => ["read", "bash"],
			getSelectedDiscoveredToolNames: () => ["mcp__github__search"],
			getDiscoverableTools: () => [{ name: "bash", label: "Bash", summary: "Run shell", source: "builtin", schemaKeys: [] }],
		} as never);
		const result = await tool.execute("catalog", {});

		expect(result.details?.activeTools).toEqual(["read"]);
		expect(result.details?.discoverableTools[0]?.name).toBe("bash");
	});

	test("prompt_preview reports active system prompt blocks", async () => {
		const tool = new PromptPreviewTool({ getSystemPrompt: () => ["alpha", "beta"] } as never);
		const result = await tool.execute("prompt", { include_blocks: true });

		expect(result.details?.blockCount).toBe(2);
		expect(result.details?.characterCount).toBe(9);
		expect(result.details?.blocks).toEqual(["alpha", "beta"]);
	});

	test("permission_rules_dump reports rules and ACP gates", async () => {
		const tool = new PermissionRulesDumpTool({
			getPermissionSnapshot: () => ({
				...emptyPermissionServiceSnapshot(),
				rules: [{ pattern: "kaji:*", decision: "allow" }],
				sessionDecisionCount: 1,
				persistentDecisionCount: 1,
				gatedAcpTools: ["bash"],
				requestCount: 2,
				denyCount: 1,
				requestCountByCategory: { host: 2 },
				denyCountByCategory: { host: 1 },
			}),
		} as never);
		const result = await tool.execute("permissions", {});

		expect(result.details?.rules[0]?.pattern).toBe("kaji:*");
		expect(result.details?.sessionDecisionCount).toBe(1);
		expect(result.details?.gatedAcpTools).toEqual(["bash"]);
		expect(result.details?.persistentDecisionCount).toBe(1);
		expect(result.content[0]?.type === "text" ? result.content[0].text : "").toContain("host:2");
	});

	test("runtime_telemetry_dump reports counters and usage", async () => {
		const tool = new RuntimeTelemetryDumpTool({
			getRuntimeTelemetrySnapshot: () => ({
				totalEvents: 8,
				toolStarts: 2,
				toolEnds: 2,
				toolFailures: 1,
				toolFailuresByName: { bash: 1 },
				toolCallsByName: { bash: 1, kaji_code_graph_search: 1 },
				codeGraphToolCalls: 1,
				autoRetryStarts: 1,
				autoRetryEnds: 1,
				autoCompactionStarts: 0,
				autoCompactionEnds: 0,
				promptRebuilds: 3,
				lastPromptCharacterCount: 1234,
				lastPromptBlockCount: 4,
				activatedMcpTools: 1,
				activatedDiscoveredTools: 2,
				lastActivatedTools: ["mcp__github__search"],
			}),
			getPermissionSnapshot: () => ({
				...emptyPermissionServiceSnapshot(),
				requestCount: 2,
				denyCount: 1,
				requestCountByCategory: { browser: 1, host: 1 },
				denyCountByCategory: { host: 1 },
			}),
			getSessionStats: () => ({
				sessionFile: null,
				sessionId: "session",
				userMessages: 1,
				assistantMessages: 1,
				toolCalls: 2,
				toolResults: 2,
				totalMessages: 4,
				tokens: { input: 10, output: 20, cacheRead: 0, cacheWrite: 0, total: 30 },
				cost: 0,
				premiumRequests: 0,
			}),
		} as never);
		const result = await tool.execute("telemetry", {});

		expect(result.details?.telemetry.codeGraphToolCalls).toBe(1);
		expect(result.details?.permission.denyCount).toBe(1);
		expect(result.content[0]?.type === "text" ? result.content[0].text : "").toContain("Session tokens: 30");
		expect(result.content[0]?.type === "text" ? result.content[0].text : "").toContain("Browser permissions: 1 asks");
	});

	test("subagent_tree_dump reports registered agents", async () => {
		const tool = new SubagentTreeDumpTool({
			agentRegistry: {
				list: () => [
					{
						id: "0-Main",
						displayName: "Main",
						kind: "main",
						status: "idle",
						sessionFile: null,
						session: null,
						createdAt: 1,
						lastActivity: 2,
					},
				],
			},
		} as never);
		const result = await tool.execute("agents", {});

		expect(result.details?.agents[0]?.id).toBe("0-Main");
		expect(result.details?.agents[0]?.kind).toBe("main");
	});

	test("debug tools are gated by debug.enabled", async () => {
		const base = {
			cwd: process.cwd(),
			hasUI: false,
			getSessionFile: () => null,
			getSessionSpawns: () => null,
		} as never;
		const disabled = await createTools({ ...base, settings: Settings.isolated({ "debug.enabled": false }) }, ["runtime_profile_dump"]);
		const enabled = await createTools({ ...base, settings: Settings.isolated({ "debug.enabled": true }) }, ["runtime_profile_dump", "runtime_telemetry_dump", "prompt_preview", "permission_rules_dump", "subagent_tree_dump"]);

		expect(disabled.map(tool => tool.name)).not.toContain("runtime_profile_dump");
		expect(enabled.map(tool => tool.name)).toContain("runtime_profile_dump");
		expect(enabled.map(tool => tool.name)).toContain("runtime_telemetry_dump");
		expect(enabled.map(tool => tool.name)).toContain("prompt_preview");
		expect(enabled.map(tool => tool.name)).toContain("permission_rules_dump");
		expect(enabled.map(tool => tool.name)).toContain("subagent_tree_dump");
	});
});
