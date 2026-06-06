import type { AgentTool, AgentToolResult } from "@oh-my-pi/pi-agent-core";
import { prompt } from "@oh-my-pi/pi-utils";
import * as z from "zod/v4";
import todoVerifyDescription from "../prompts/tools/todo-verify.md" with { type: "text" };
import type { ToolSession } from "../sdk";
import { formatTodoReadResult, summarizeTodoPhases, type TodoReadSummary } from "./todo-read";
import type { TodoPhase } from "./todo-write";

const todoVerifySchema = z
	.object({
		completion_claim: z.string().optional().describe("Short statement of what is being claimed as complete"),
		allow_incomplete: z.boolean().optional().describe("Set true only when intentionally reporting incomplete work"),
	})
	.describe("verify todo completion before final response");

type TodoVerifyParams = z.infer<typeof todoVerifySchema>;

export interface TodoVerifyToolDetails {
	verified: boolean;
	completionClaim?: string;
	phases: TodoPhase[];
	summary: TodoReadSummary;
	incomplete: Array<{ phase: string; content: string; status: "pending" | "in_progress" }>;
}

export function collectIncompleteTodos(phases: TodoPhase[]): TodoVerifyToolDetails["incomplete"] {
	return phases.flatMap(phase =>
		phase.tasks
			.filter((task): task is typeof task & { status: "pending" | "in_progress" } => {
				return task.status === "pending" || task.status === "in_progress";
			})
			.map(task => ({ phase: phase.name, content: task.content, status: task.status })),
	);
}

export class TodoVerifyTool implements AgentTool<typeof todoVerifySchema, TodoVerifyToolDetails> {
	readonly name = "todo_verify";
	readonly approval = "read" as const;
	readonly label = "Todo Verify";
	readonly summary = "Verify todos before claiming completion";
	readonly description = prompt.render(todoVerifyDescription);
	readonly parameters = todoVerifySchema;
	readonly strict = true;
	readonly loadMode = "discoverable";

	constructor(private readonly session: ToolSession) {}

	async execute(_toolCallId: string, params: TodoVerifyParams): Promise<AgentToolResult<TodoVerifyToolDetails>> {
		const phases = this.session.getTodoPhases?.() ?? [];
		const summary = summarizeTodoPhases(phases);
		const incomplete = collectIncompleteTodos(phases);
		const verified = incomplete.length === 0;
		const details = {
			verified,
			completionClaim: params.completion_claim,
			phases,
			summary,
			incomplete,
		};
		if (verified || params.allow_incomplete === true) {
			return { content: [{ type: "text", text: formatVerificationSuccess(phases, verified) }], details };
		}
		return {
			content: [{ type: "text", text: formatVerificationFailure(phases, incomplete) }],
			details,
			isError: true,
		};
	}
}

function formatVerificationSuccess(phases: TodoPhase[], verified: boolean): string {
	if (verified) return "Todo verification passed. No pending or in-progress todos remain.";
	return `Todo verification recorded incomplete work intentionally.\n\n${formatTodoReadResult(phases)}`;
}

function formatVerificationFailure(phases: TodoPhase[], incomplete: TodoVerifyToolDetails["incomplete"]): string {
	const list = incomplete.map(item => `- ${item.phase}: ${item.content} (${item.status})`).join("\n");
	return [
		`Todo verification failed. ${incomplete.length} todo item(s) are still incomplete:`,
		list,
		"Do not claim completion until these are finished or explicitly report the work as incomplete.",
		"",
		formatTodoReadResult(phases),
	].join("\n");
}
