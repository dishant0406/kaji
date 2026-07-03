import { describe, expect, test } from "bun:test";
import { extractPermissionLocations, getPermissionIntent } from "./permission-intent";
import { matchPermissionPattern } from "./permission-pattern";
import type { ClientBridge } from "../session/client-bridge";
import { loadPermissionDecisionsFromEntries, PERMISSION_DECISION_CUSTOM_TYPE } from "./permission-decision-store";
import { PermissionService, permissionKeyForTool } from "./permission-service";

describe("PermissionService", () => {
	test("matches wildcard permission patterns", () => {
		expect(matchPermissionPattern("mcp:*", "mcp:github_search")).toBe(true);
		expect(matchPermissionPattern("kaji:code_graph_*", "kaji:code_graph_search")).toBe(true);
		expect(matchPermissionPattern("kaji:code_graph_*", "kaji:open_file")).toBe(false);
	});

	test("resolves last matching rule", () => {
		const service = new PermissionService();
		service.setRules([
			{ pattern: "mcp:*", decision: "prompt" },
			{ pattern: "mcp:github_*", decision: "allow" },
		]);
		expect(service.resolve({ key: "mcp:github_search", toolName: "mcp__github__search" })).toBe("allow");
		expect(service.resolve({ key: "mcp:linear_search", toolName: "mcp__linear__search" })).toBe("prompt");
	});

	test("detects destructive edit intents from structured edits and patches", () => {
		expect(getPermissionIntent("edit", { path: "a.ts", edits: [{ op: "delete" }] })?.cacheKey).toBe("edit:delete");
		expect(
			getPermissionIntent("edit", {
				input: "*** Begin Patch\n*** Delete File: old.ts\n*** End Patch\n",
			})?.paths,
		).toEqual(["old.ts"]);
	});

	test("normalizes permission locations against cwd", () => {
		expect(extractPermissionLocations({ paths: ["src/a.ts", "src/a.ts"] }, "/tmp/project")).toEqual([
			{ path: "/tmp/project/src/a.ts" },
		]);
	});

	test("maps tool names to central permission keys", () => {
		expect(permissionKeyForTool("mcp__github__search")).toBe("mcp:mcp__github__search");
			expect(permissionKeyForTool("kaji_fff_search")).toBe("kaji:kaji_fff_search");
		expect(permissionKeyForTool("undo")).toBe("write");
		expect(permissionKeyForTool("browser")).toBe("browser");
	});

	test("authorizes runtime tool calls through central rules and approval policy", async () => {
		const service = new PermissionService();
		let approvalAsked = false;

		await expect(
			service.authorizeRuntimeToolCall({
				tool: { name: "bash", approval: "exec" },
				args: {},
				approvalMode: "always-ask",
				hasUI: false,
				requestApproval: async () => true,
			}),
		).rejects.toThrow(/requires approval/);

		await service.authorizeRuntimeToolCall({
			tool: { name: "bash", approval: "exec" },
			args: {},
			approvalMode: "always-ask",
			hasUI: true,
			requestApproval: async () => {
				approvalAsked = true;
				return true;
			},
		});

		expect(approvalAsked).toBe(true);
		expect(service.snapshot().requestCount).toBe(1);
		expect(service.snapshot().denyCount).toBe(1);
		service.setRules([{ pattern: "bash", decision: "deny" }]);
		await expect(
			service.authorizeRuntimeToolCall({
				tool: { name: "bash", approval: "read" },
				args: {},
				approvalMode: "yolo",
				hasUI: true,
				requestApproval: async () => true,
			}),
		).rejects.toThrow(/permission policy/);
		expect(service.snapshot().denyCount).toBe(2);
	});
	test("persists always ACP decisions through the injected session store", async () => {
		const entries: Array<{ type: string; customType?: string; data?: unknown }> = [];
		const persistence = {
			load: () => loadPermissionDecisionsFromEntries(entries),
			save: decision => {
				entries.push({ type: "custom", customType: PERMISSION_DECISION_CUSTOM_TYPE, data: decision });
			},
		};
		const bridge = acpBridge("allow_always");
		const service = new PermissionService(persistence);

		await service.authorizeAcpToolCall({
			bridge,
			toolCallId: "call",
			toolName: "bash",
			args: { command: "rm -rf tmp" },
			cwd: "/tmp/project",
		});
		const rehydrated = new PermissionService(persistence);
		await rehydrated.authorizeAcpToolCall({
			bridge,
			toolCallId: "call-2",
			toolName: "bash",
			args: { command: "rm -rf tmp" },
			cwd: "/tmp/project",
		});

		expect(bridge.requestCount).toBe(1);
		expect(rehydrated.snapshot().persistentDecisionCount).toBe(1);
		expect(rehydrated.snapshot().persistentDecisions[0]?.duration).toBe("always");
	});

	test("tracks permission telemetry by browser and host categories", async () => {
		const service = new PermissionService();
		await service.authorizeRuntimeToolCall({
			tool: { name: "browser", approval: "exec" },
			args: {},
			approvalMode: "always-ask",
			hasUI: true,
			requestApproval: async () => true,
		});
		service.setRules([{ pattern: "kaji:*", decision: "deny" }]);
		await expect(
			service.authorizeRuntimeToolCall({
				tool: { name: "kaji_open_file", approval: "read" },
				args: {},
				approvalMode: "yolo",
				hasUI: true,
				requestApproval: async () => true,
			}),
		).rejects.toThrow(/permission policy/);

		const snapshot = service.snapshot();
		expect(snapshot.requestCountByKey.browser).toBe(1);
		expect(snapshot.requestCountByCategory.browser).toBe(1);
		expect(snapshot.denyCountByKey["kaji:kaji_open_file"]).toBe(1);
		expect(snapshot.denyCountByCategory.host).toBe(1);
	});

});


function acpBridge(optionId: "allow_always" | "reject_always") {
	let requestCount = 0;
	const bridge = {
		capabilities: { requestPermission: true },
		requestPermission: async () => {
			requestCount++;
			return { outcome: "selected" as const, optionId };
		},
	};
	return Object.defineProperty(bridge, "requestCount", { get: () => requestCount }) as ClientBridge & {
		requestCount: number;
	};
}
