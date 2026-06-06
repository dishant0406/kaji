import type { AgentTool, AgentToolResult } from "@oh-my-pi/pi-agent-core";
import { prompt } from "@oh-my-pi/pi-utils";
import * as z from "zod/v4";
import todoReadDescription from "../prompts/tools/todo-read.md" with { type: "text" };
import type { ToolSession } from "../sdk";
import { phasesToMarkdown, type TodoPhase } from "./todo-write";

const todoReadSchema = z.object({}).describe("read the current session todo list");

export interface TodoReadToolDetails {
	phases: TodoPhase[];
	summary: TodoReadSummary;
}

export interface TodoReadSummary {
	total: number;
	pending: number;
	inProgress: number;
	completed: number;
	abandoned: number;
}

export function summarizeTodoPhases(phases: TodoPhase[]): TodoReadSummary {
	const tasks = phases.flatMap(phase => phase.tasks);
	return {
		total: tasks.length,
		pending: tasks.filter(task => task.status === "pending").length,
		inProgress: tasks.filter(task => task.status === "in_progress").length,
		completed: tasks.filter(task => task.status === "completed").length,
		abandoned: tasks.filter(task => task.status === "abandoned").length,
	};
}

export function formatTodoReadResult(phases: TodoPhase[]): string {
	const summary = summarizeTodoPhases(phases);
	if (summary.total === 0) return "No todos are currently tracked for this session.";
	const header = [
		`Todos: ${summary.total} total`,
		`${summary.pending} pending`,
		`${summary.inProgress} in progress`,
		`${summary.completed} completed`,
		`${summary.abandoned} abandoned`,
	].join("; ");
	return `${header}\n\n${phasesToMarkdown(phases).trimEnd()}`;
}

export class TodoReadTool implements AgentTool<typeof todoReadSchema, TodoReadToolDetails> {
	readonly name = "todo_read";
	readonly approval = "read" as const;
	readonly label = "Todo Read";
	readonly summary = "Read the current structured todo list";
	readonly description = prompt.render(todoReadDescription);
	readonly parameters = todoReadSchema;
	readonly strict = true;
	readonly loadMode = "discoverable";

	constructor(private readonly session: ToolSession) {}

	async execute(): Promise<AgentToolResult<TodoReadToolDetails>> {
		const phases = this.session.getTodoPhases?.() ?? [];
		return {
			content: [{ type: "text", text: formatTodoReadResult(phases) }],
			details: { phases, summary: summarizeTodoPhases(phases) },
		};
	}
}
