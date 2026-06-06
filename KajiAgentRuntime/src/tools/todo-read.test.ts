import { describe, expect, test } from "bun:test";
import { Settings } from "../config/settings";
import { createTools, type ToolSession } from "./index";
import { formatTodoReadResult, summarizeTodoPhases, TodoReadTool } from "./todo-read";
import type { TodoPhase } from "./todo-write";

const phases: TodoPhase[] = [
	{
		name: "Build",
		tasks: [
			{ content: "Implement todo_read", status: "completed" },
			{ content: "Run tests", status: "in_progress" },
		],
	},
	{
		name: "Ship",
		tasks: [{ content: "Document behavior", status: "pending" }],
	},
];

describe("todo_read", () => {
	test("summarizes current todo phases", () => {
		expect(summarizeTodoPhases(phases)).toEqual({
			total: 3,
			pending: 1,
			inProgress: 1,
			completed: 1,
			abandoned: 0,
		});
	});

	test("formats markdown without mutating todo state", () => {
		const rendered = formatTodoReadResult(phases);

		expect(rendered).toContain("Todos: 3 total; 1 pending; 1 in progress; 1 completed; 0 abandoned");
		expect(rendered).toContain("# Build");
		expect(rendered).toContain("- [x] Implement todo_read");
		expect(rendered).toContain("- [/] Run tests");
	});

	test("tool returns session phases and summary details", async () => {
		const tool = new TodoReadTool({ getTodoPhases: () => phases } as ToolSession);

		const result = await tool.execute();

		expect(result.content[0]?.text).toContain("Todos: 3 total");
		expect(result.details?.phases).toBe(phases);
		expect(result.details?.summary.total).toBe(3);
	});

	test("createTools exposes todo_read when todo is enabled", async () => {
		const settings = Settings.isolated({ "todo.enabled": true });
		const session: ToolSession = {
			cwd: "/tmp/kaji-todo-read-test",
			hasUI: false,
			getSessionFile: () => null,
			getSessionSpawns: () => null,
			settings,
			skipPythonPreflight: true,
		};

		const tools = await createTools(session, ["todo_read"]);

		expect(tools.map(tool => tool.name)).toEqual(["todo_read", "resolve"]);
	});
});
