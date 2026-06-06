import { describe, expect, test } from "bun:test";
import { Settings } from "../config/settings";
import { createTools } from ".";
import { collectIncompleteTodos, TodoVerifyTool } from "./todo-verify";
import type { TodoPhase } from "./todo-write";

const phases: TodoPhase[] = [
	{
		id: "phase-1",
		name: "Build",
		tasks: [
			{ content: "done", status: "completed" },
			{ content: "remaining", status: "pending" },
		],
	},
];

describe("todo_verify", () => {
	test("collects incomplete pending and in-progress todos", () => {
		expect(collectIncompleteTodos(phases)).toEqual([{ phase: "Build", content: "remaining", status: "pending" }]);
	});

	test("fails closed when claiming completion with incomplete todos", async () => {
		const tool = new TodoVerifyTool({ getTodoPhases: () => phases } as never);
		const result = await tool.execute("verify", { completion_claim: "finished" });

		expect(result.isError).toBe(true);
		expect(result.details?.verified).toBe(false);
		expect(result.content[0]?.type === "text" ? result.content[0].text : "").toContain("Todo verification failed");
	});

	test("passes when no incomplete todos remain", async () => {
		const tool = new TodoVerifyTool({ getTodoPhases: () => [{ ...phases[0]!, tasks: [{ content: "done", status: "completed" }] }] } as never);
		const result = await tool.execute("verify", {});

		expect(result.isError).toBeUndefined();
		expect(result.details?.verified).toBe(true);
	});

	test("createTools exposes todo_verify when todo is enabled", async () => {
		const tools = await createTools(
			{
				cwd: process.cwd(),
				hasUI: false,
				settings: Settings.isolated({ "todo.enabled": true }),
				getSessionFile: () => null,
				getSessionSpawns: () => null,
			} as never,
			["todo_verify"],
		);

		expect(tools.map(tool => tool.name)).toContain("todo_verify");
	});
});
