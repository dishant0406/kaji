import { describe, expect, test } from "bun:test";
import * as fs from "node:fs/promises";
import * as os from "node:os";
import * as path from "node:path";
import { Settings } from "../src/config/settings";
import { RpcHostToolBridge } from "../src/modes/rpc/host-tools";
import type { RpcHostToolCallRequest } from "../src/modes/rpc/rpc-types";
import { kajiRpcPlanRuntimeProfile, kajiRpcRuntimeProfile } from "../src/runtime/profile";
import { buildSystemPrompt } from "../src/system-prompt";
import { createTools, type ToolSession } from "../src/tools";

const workspaceTree = {
	rootPath: "/tmp/kaji-runtime-snapshot",
	rendered: ".\n  - KajiAgentRuntime/        1m",
	truncated: false,
	totalLines: 2,
	agentsMdFiles: [],
};

describe("runtime harness snapshots", () => {
	test("default Kaji RPC prompt fixture includes native harness sections", async () => {
		await withTempDir(async dir => {
			const toolNames = [
				"read",
				"search",
				"lsp",
				"todo_verify",
				"undo",
				"kaji_code_graph_search",
				"kaji_get_open_tabs",
				"runtime_telemetry_dump",
				"permission_rules_dump",
			];
			const { systemPrompt } = await buildSystemPrompt({
				cwd: dir,
				contextFiles: [],
				skills: [],
				rules: [],
				toolNames,
				tools: metadata(toolNames),
				workspaceTree: { ...workspaceTree, rootPath: dir },
				mcpDiscoveryMode: true,
				mcpDiscoveryServerSummaries: ["github (2 tools)"],
			});

			expect(promptFixture(systemPrompt)).toEqual({
				blockCount: 2,
				hasKajiHarness: true,
				hasDiscovery: true,
				hasCodeGraph: true,
				hasWorkspaceContext: true,
				hasTodoVerification: true,
				hasEditSafety: true,
				hasRuntimeDebugging: true,
				projectHasWorkspaceTree: true,
			});
		});
	});

	test("runtime profile tool fixtures preserve build and plan harness shape", async () => {
		const session = toolSession();
		const buildTools = await createTools(session, [...kajiRpcRuntimeProfile().toolPatterns]);
		const planTools = await createTools(session, [...kajiRpcPlanRuntimeProfile().toolPatterns]);

		expect(buildTools.map(tool => tool.name)).toEqual([
			"read",
			"bash",
			"edit",
			"undo",
			"task",
			"todo_write",
			"todo_read",
			"todo_verify",
			"find",
			"search",
			"lsp",
			"runtime_profile_dump",
			"runtime_telemetry_dump",
			"tool_catalog_dump",
			"prompt_preview",
			"permission_rules_dump",
			"subagent_tree_dump",
			"resolve",
		]);
		expect(planTools.map(tool => tool.name)).toEqual([
			"read",
			"find",
			"search",
			"lsp",
			"task",
			"todo_read",
			"todo_verify",
			"resolve",
		]);
	});

	test("RPC host tool frame fixture preserves Kaji native tool calls", async () => {
		const frames: RpcHostToolCallRequest[] = [];
		const bridge = new RpcHostToolBridge(frame => {
			if (frame.type === "host_tool_call") frames.push(frame);
		});
		const [tool] = bridge.setTools([
			{
				name: "kaji_get_open_tabs",
				label: "Open Tabs",
				description: "Returns native Kaji open tabs",
				approval: "read",
				parameters: { type: "object", properties: { limit: { type: "number" } }, additionalProperties: false },
			},
		]);
		const result = tool.execute("tool-call", { limit: 5 });
		const frame = frames[0];
		if (!frame) throw new Error("Expected host tool call frame");
		bridge.handleResult({ type: "host_tool_result", id: frame.id, result: { content: [{ type: "text", text: "ok" }] } });

		expect({ toolName: tool.name, approval: tool.approval, frame }).toMatchObject({
			toolName: "kaji_get_open_tabs",
			approval: "read",
			frame: { type: "host_tool_call", toolCallId: "tool-call", toolName: "kaji_get_open_tabs", arguments: { limit: 5 } },
		});
		await expect(result).resolves.toEqual({ content: [{ type: "text", text: "ok" }] });
	});
});

function promptFixture(blocks: string[]) {
	const text = blocks.join("\n\n");
	return {
		blockCount: blocks.length,
		hasKajiHarness: text.includes("You operate within the Kaji Agent coding harness."),
		hasDiscovery: text.includes("## Discovery") && text.includes("github (2 tools)"),
		hasCodeGraph: text.includes("## Kaji Code Graph"),
		hasWorkspaceContext: text.includes("## Kaji Workspace Context"),
		hasTodoVerification: text.includes("## Todo Verification"),
		hasEditSafety: text.includes("## Edit Safety"),
		hasRuntimeDebugging: text.includes("## Runtime Debugging"),
		projectHasWorkspaceTree: blocks[1]?.includes("<workspace-tree>") === true,
	};
}

function metadata(toolNames: string[]) {
	return new Map(toolNames.map(name => [name, { label: name.replaceAll("_", " "), description: `${name} description` }]));
}

function toolSession(): ToolSession {
	return {
		cwd: "/tmp/kaji-runtime-snapshot",
		hasUI: false,
		getSessionFile: () => null,
		getSessionSpawns: () => null,
		settings: Settings.isolated({
			"debug.enabled": true,
			"todo.enabled": true,
			"find.enabled": true,
			"search.enabled": true,
			"lsp.enabled": true,
			"astGrep.enabled": false,
			"astEdit.enabled": false,
			"tools.discoveryMode": "off",
		}),
		skipPythonPreflight: true,
	};
}

async function withTempDir(run: (dir: string) => Promise<void>): Promise<void> {
	const dir = await fs.mkdtemp(path.join(os.tmpdir(), "kaji-runtime-snapshot-"));
	try {
		await run(dir);
	} finally {
		await fs.rm(dir, { recursive: true, force: true });
	}
}
