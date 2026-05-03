import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import readline from "node:readline";
import { Agent, type AgentEvent, type AgentTool, type AgentToolResult, type ThinkingLevel } from "@mariozechner/pi-agent-core";
import { type Api, getEnvApiKey, getModels, type KnownProvider, type Model, Type } from "@mariozechner/pi-ai";
import { getOAuthApiKey, type OAuthCredentials } from "@mariozechner/pi-ai/oauth";

type ProtocolMessage = {
	type: string;
	taskID?: string;
	prompt?: string;
	id?: string;
	ok?: boolean;
	result?: unknown;
};

type PendingTool = {
	resolve: (value: unknown) => void;
	reject: (error: Error) => void;
};

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Number.POSITIVE_INFINITY });
const pendingTools = new Map<string, PendingTool>();
const sessions = new Map<string, Agent>();
const supervisedRunIDsBySession = new Map<string, Set<string>>();
let activeTaskID: string | undefined;

function send(message: Record<string, unknown>) {
	process.stdout.write(`${JSON.stringify(message)}\n`);
}

function createID(prefix: string) {
	return `${prefix}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function selectedModel(): Model<Api> | undefined {
	const provider = process.env.DROID_PARENT_PROVIDER ?? "anthropic";
	const modelID = process.env.DROID_PARENT_MODEL ?? "claude-sonnet-4-5";
	return getModels(provider as KnownProvider).find((model) => model.id === modelID) as Model<Api> | undefined;
}

function selectedThinking(): ThinkingLevel {
	const value = process.env.DROID_PARENT_THINKING ?? "off";
	if (value === "minimal" || value === "low" || value === "medium" || value === "high" || value === "xhigh") return value;
	return "off";
}

function authPath() {
	return join(homedir(), ".pi", "agent", "auth.json");
}

function readAuthFile(): Record<string, { type?: string; key?: string } & OAuthCredentials> {
	const path = authPath();
	if (!existsSync(path)) return {};
	return JSON.parse(readFileSync(path, "utf8")) as Record<string, { type?: string; key?: string } & OAuthCredentials>;
}

function writeAuthFile(auth: Record<string, unknown>) {
	writeFileSync(authPath(), `${JSON.stringify(auth, null, 2)}\n`, "utf8");
}

async function resolveApiKey(provider: string) {
	const envKey = getEnvApiKey(provider);
	if (envKey) return envKey;

	const auth = readAuthFile();
	const credential = auth[provider];
	if (credential?.type === "api_key" && credential.key) {
		return process.env[credential.key] ?? credential.key;
	}
	if (credential?.type === "oauth") {
		const result = await getOAuthApiKey(provider, auth);
		if (!result) return undefined;
		auth[provider] = { ...result.newCredentials, type: "oauth" };
		writeAuthFile(auth);
		return result.apiKey;
	}
	return undefined;
}

function systemPrompt() {
	return [
		"You are Droid's parent agent.",
		"You control Droid by calling Droid tools, not by inventing shell commands.",
		"Use Droid tools to inspect projects, spawn child coding agents, observe them, and report final results.",
		"Do not spawn multiple child agents by default. Start with one worker, observe it, and wait for useful output before starting another.",
		"Only spawn additional child agents when the user explicitly asks for parallel work, the first worker fails, or a clearly separate verification/review worker is necessary.",
		"When you spawn child agents, supervise them explicitly: observe, reason, sleep briefly if still running, then observe again.",
		"Do not claim a child agent is done until droid_observe_agents shows a meaningful final answer or useful completed output.",
		"If an agent is still running, call droid_sleep and then droid_observe_agents again.",
		"Be concise and honest about what has or has not been executed.",
	].join("\n");
}

function droidProtocolToolName(name: string) {
	if (name === "droid_list_projects") return "droid.list_projects";
	if (name === "droid_get_active_context") return "droid.get_active_context";
	if (name === "droid_ask_user") return "droid.ask_user";
	if (name === "droid_spawn_agent") return "droid.spawn_agent";
	if (name === "droid_send_prompt") return "droid.send_prompt";
	if (name === "droid_get_agent_status") return "droid.get_agent_status";
	if (name === "droid_observe_agents") return "droid.observe_agents";
	if (name === "droid_sleep") return "droid.sleep";
	if (name === "droid_jump_to_agent") return "droid.jump_to_agent";
	return name;
}

function stringifyResult(result: unknown) {
	if (typeof result === "string") return result;
	return JSON.stringify(result, null, 2);
}

function callDroidTool(name: string, args: Record<string, unknown>, taskID: string | undefined): Promise<unknown> {
	const id = createID("tool");
	const promise = new Promise<unknown>((resolve, reject) => pendingTools.set(id, { resolve, reject }));
	send({ type: "tool_call", id, taskID, name: droidProtocolToolName(name), arguments: args });
	return promise;
}

function tool(name: string, description: string, parameters: ReturnType<typeof Type.Object>): AgentTool {
	return {
		name,
		label: name,
		description,
		parameters,
		execute: async (_toolCallId, params, signal): Promise<AgentToolResult<unknown>> => {
			if (signal?.aborted) throw new Error("Tool call aborted");
		const result = await callDroidTool(name, params as Record<string, unknown>, activeTaskID);
			trackDroidToolResult(name, result);
			return { content: [{ type: "text", text: stringifyResult(result) }], details: result };
		},
	};
}

function droidTools(): AgentTool[] {
	return [
		tool("droid_list_projects", "List projects available in Droid.", Type.Object({})),
		tool("droid_get_active_context", "Get Droid's active project and workspace context.", Type.Object({})),
		tool("droid_ask_user", "Ask the user one concise question when required information is missing.", Type.Object({ question: Type.String() })),
		tool(
			"droid_spawn_agent",
			"Start one terminal coding agent in Droid. Providers: codex, claude, opencode, terminal. Droid enforces one active worker per parent task unless the user explicitly requested parallel work and allowParallel is true. If rejected, observe the returned existing run instead.",
			Type.Object({
				prompt: Type.String(),
				provider: Type.Optional(Type.String()),
				project: Type.Optional(Type.String()),
				allowParallel: Type.Optional(Type.String()),
			}),
		),
		tool("droid_send_prompt", "Send a follow-up prompt to an existing child agent run by runID.", Type.Object({ runID: Type.String(), prompt: Type.String() })),
		tool("droid_get_agent_status", "Get recent child agent run status from Droid.", Type.Object({})),
		tool("droid_observe_agents", "Observe live child agent run status, recent events, and transcript snippets.", Type.Object({ runIDs: Type.Optional(Type.String()) })),
		tool("droid_sleep", "Pause briefly before observing child agents again. Use seconds between 3 and 30.", Type.Object({ seconds: Type.Optional(Type.String()), reason: Type.Optional(Type.String()) })),
		tool("droid_jump_to_agent", "Navigate Droid to a child agent run by runID.", Type.Object({ runID: Type.String() })),
	];
}

function trackDroidToolResult(toolName: string, result: unknown) {
	if (toolName === "droid_observe_agents" || toolName === "droid_get_agent_status") {
		updateSupervisedRunsFromObservation(result);
		return;
	}
	if (toolName !== "droid_spawn_agent") return;
	const childRun = result && typeof result === "object" && "childRun" in result ? result.childRun : undefined;
	if (!childRun || typeof childRun !== "object" || !("id" in childRun) || typeof childRun.id !== "string") return;
	const sessionID = activeTaskID ?? "default";
	const set = supervisedRunIDsBySession.get(sessionID) ?? new Set<string>();
	set.add(childRun.id);
	supervisedRunIDsBySession.set(sessionID, set);
}

function updateSupervisedRunsFromObservation(result: unknown) {
	if (!result || typeof result !== "object" || !("childRuns" in result) || !Array.isArray(result.childRuns)) return;
	const sessionID = activeTaskID ?? "default";
	const set = supervisedRunIDsBySession.get(sessionID);
	if (!set) return;
	for (const run of result.childRuns) {
		if (!run || typeof run !== "object" || !("id" in run) || typeof run.id !== "string") continue;
		if (isClosedRun(run)) set.delete(run.id);
	}
	supervisedRunIDsBySession.set(sessionID, set);
}

function isClosedRun(run: Record<string, unknown>) {
	const status = String(run.status ?? "");
	return status === "completed" || status === "failed" || status === "stale";
}

function supervisedRunIDs(sessionID: string) {
	return Array.from(supervisedRunIDsBySession.get(sessionID) ?? []);
}

function observePrompt(sessionID: string) {
	const ids = supervisedRunIDs(sessionID);
	return [
		"Continue supervising the child agents.",
		ids.length > 0 ? `Use droid_observe_agents with runIDs: ${ids.join(",")}.` : "Use droid_observe_agents.",
		"If any child agent is still running, think briefly, call droid_sleep, then observe again.",
		"Only answer the user after you have a meaningful final result from the child agent feed.",
	].join(" ");
}

function handleAgentEvent(event: AgentEvent) {
	if (event.type === "message_update") {
		const streamEvent = event.assistantMessageEvent;
		if (streamEvent.type === "text_delta") send({ type: "assistant_delta", taskID: activeTaskID, message: streamEvent.delta });
		if (streamEvent.type === "thinking_delta") send({ type: "thinking_delta", taskID: activeTaskID, message: streamEvent.delta });
		if (streamEvent.type === "thinking_end") send({ type: "thinking_end", taskID: activeTaskID });
		if (streamEvent.type === "toolcall_end") send({ type: "task_event", taskID: activeTaskID, event: "tool.requested", message: streamEvent.toolCall.name });
	}
	if (event.type === "tool_execution_start") send({ type: "task_event", taskID: activeTaskID, event: "tool.started", message: event.toolName });
	if (event.type === "tool_execution_end") send({ type: "task_event", taskID: activeTaskID, event: "tool.completed", message: event.toolName });
}

function createAgent(model: Model<Api>) {
	const agent = new Agent({
		initialState: {
			systemPrompt: systemPrompt(),
			model,
			thinkingLevel: selectedThinking(),
			tools: droidTools(),
		},
		getApiKey: (provider) => resolveApiKey(provider),
		toolExecution: "sequential",
	});
	agent.subscribe((event) => handleAgentEvent(event));
	return agent;
}

function latestAssistantStopReason(agent: Agent) {
	for (let index = agent.state.messages.length - 1; index >= 0; index--) {
		const message = agent.state.messages[index];
		if (message?.role === "assistant") return message.stopReason;
	}
	return undefined;
}

async function runPrompt(message: ProtocolMessage) {
	activeTaskID = message.taskID;
	const model = selectedModel();
	if (!model) {
		send({ type: "error", taskID: message.taskID, message: "Parent model was not found." });
		return;
	}
	if (!(await resolveApiKey(model.provider))) {
		send({ type: "error", taskID: message.taskID, message: `Missing API key for ${model.provider}.` });
		return;
	}

	send({ type: "task_event", taskID: message.taskID, event: "task.planning", message: `Using ${model.provider}/${model.id}.` });
	const sessionID = message.taskID ?? "default";
	const agent = sessions.get(sessionID) ?? createAgent(model);
	sessions.set(sessionID, agent);
	await agent.prompt(message.prompt ?? "");

	for (let i = 0; i < 24 && supervisedRunIDs(sessionID).length > 0; i++) {
		agent.followUp({ role: "user", content: [{ type: "text", text: observePrompt(sessionID) }], timestamp: Date.now() });
		await agent.continue();
		if (supervisedRunIDs(sessionID).length === 0) break;
		const stopReason = latestAssistantStopReason(agent);
		if (stopReason && stopReason !== "toolUse") {
			agent.followUp({ role: "user", content: [{ type: "text", text: observePrompt(sessionID) }], timestamp: Date.now() });
		}
	}
	send({ type: "final_response", taskID: message.taskID, message: "Parent agent turn completed." });
}

function handleToolResult(message: ProtocolMessage) {
	if (!message.id) return;
	const pending = pendingTools.get(message.id);
	if (!pending) return;
	pendingTools.delete(message.id);
	if (message.ok === false) pending.reject(new Error(stringifyResult(message.result)));
	else pending.resolve(message.result);
}

rl.on("line", (line) => {
	try {
		const message = JSON.parse(line) as ProtocolMessage;
		if (message.type === "user_prompt") void runPrompt(message);
		if (message.type === "tool_result") handleToolResult(message);
	} catch (error) {
		send({ type: "error", taskID: activeTaskID, message: error instanceof Error ? error.message : String(error) });
	}
});

send({ type: "heartbeat", message: "droid-pi-parent-agent-ready" });
