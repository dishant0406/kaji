import { describe, expect, test } from "bun:test";
import { Settings } from "../config/settings";
import type { ToolSession } from "./index";
import { createTools } from "./index";
import { resolveToolEntries, resolveToolNames, toolPatternMatches } from "./tool-resolver";

describe("tool resolver", () => {
	test("resolves exact names in requested order", () => {
		const result = resolveToolNames(["read", "bash", "edit"], ["edit", "read"]);

		expect(result.entries.map(entry => entry.name)).toEqual(["edit", "read"]);
		expect(result.unknown).toEqual([]);
	});

	test("supports glob patterns and deduplicates by resolved tool name", () => {
		const result = resolveToolNames(["read", "ast_grep", "ast_edit", "bash"], ["ast_*", "ast_grep"]);

		expect(result.entries.map(entry => entry.name)).toEqual(["ast_grep", "ast_edit"]);
		expect(result.unknown).toEqual([]);
	});

	test("normalizes deprecated aliases", () => {
		const result = resolveToolNames(["read", "write", "task", "search"], ["Read", "Task", "fs_search"]);

		expect(result.entries.map(entry => entry.name)).toEqual(["read", "task", "search"]);
		expect(result.unknown).toEqual([]);
	});

	test("tracks unknown patterns without dropping valid matches", () => {
		const result = resolveToolNames(["read", "bash"], ["missing", "read"]);

		expect(result.entries.map(entry => entry.name)).toEqual(["read"]);
		expect(result.unknown).toEqual(["missing"]);
	});

	test("preserves values when resolving entries", () => {
		const result = resolveToolEntries(
			[
				{ name: "read", value: 1 },
				{ name: "write", value: 2 },
			],
			["write"],
		);

		expect(result.entries).toEqual([{ name: "write", value: 2 }]);
	});

	test("matches only full tool names", () => {
		expect(toolPatternMatches("ast_*", "ast_edit")).toBe(true);
		expect(toolPatternMatches("ast_*", "x_ast_edit")).toBe(false);
		expect(toolPatternMatches("read", "read_file")).toBe(false);
	});

	test("is used by createTools for aliases and glob requests", async () => {
		const settings = Settings.isolated({
			"astGrep.enabled": true,
			"astEdit.enabled": true,
			"find.enabled": true,
			"search.enabled": true,
			"lsp.enabled": false,
			"todo.enabled": false,
			"tools.discoveryMode": "off",
		});
		const session: ToolSession = {
			cwd: "/tmp/kaji-tool-resolver-test",
			hasUI: false,
			getSessionFile: () => null,
			getSessionSpawns: () => null,
			settings,
			skipPythonPreflight: true,
		};

		const tools = await createTools(session, ["Read", "fs_search", "ast_*"]);

		expect(tools.map(tool => tool.name)).toEqual(["read", "search", "ast_grep", "ast_edit", "resolve"]);
	});
});
