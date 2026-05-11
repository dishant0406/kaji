import { execFile } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve, sep } from "node:path";
import readline from "node:readline";
import { promisify } from "node:util";
import {
	Agent,
	type AgentEvent,
	type AgentTool,
	type AgentToolResult,
	type ThinkingLevel,
} from "@mariozechner/pi-agent-core";
import {
	type Api,
	getEnvApiKey,
	getModels,
	type ImageContent,
	type KnownProvider,
	type Model,
	type TextContent,
	Type,
} from "@mariozechner/pi-ai";
import { getOAuthApiKey, type OAuthCredentials } from "@mariozechner/pi-ai/oauth";

type ProtocolMessage = {
	type: string;
	taskID?: string;
	prompt?: string;
	attachments?: ProtocolAttachment[];
	id?: string;
	ok?: boolean;
	result?: unknown;
};

type ProtocolAttachment = {
	name: string;
	path: string;
	kind: string;
	mimeType: string;
	data?: string;
};

type PendingTool = {
	resolve: (value: unknown) => void;
	reject: (error: Error) => void;
};

type RuntimeContext = {
	taskID?: string;
	sessionID: string;
};

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Number.POSITIVE_INFINITY });
const pendingTools = new Map<string, PendingTool>();
const sessions = new Map<string, Agent>();
const execFileAsync = promisify(execFile);
let promptQueue = Promise.resolve();

function send(message: Record<string, unknown>) {
	process.stdout.write(`${JSON.stringify(message)}\n`);
}

function createID(prefix: string) {
	return `${prefix}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function selectedModel(): Model<Api> | undefined {
	const provider = process.env.KAJI_PARENT_PROVIDER ?? "anthropic";
	const modelID = process.env.KAJI_PARENT_MODEL ?? "claude-sonnet-4-5";
	return getModels(provider as KnownProvider).find((model) => model.id === modelID) as Model<Api> | undefined;
}

function selectedThinking(): ThinkingLevel {
	const value = process.env.KAJI_PARENT_THINKING ?? "off";
	if (value === "minimal" || value === "low" || value === "medium" || value === "high" || value === "xhigh")
		return value;
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
	if (agentMode() === "kajicodegraph") return graphSystemPrompt();
	return [
		"You are Kaji's parent agent.",
		"You control Kaji by calling Kaji tools, not by inventing shell commands.",
		"Use Kaji tools to inspect projects, spawn child coding agents, observe them, and answer with the final outcome directly.",
		"Do not add a separate result summary/card after already giving the final answer.",
		"Only use coding agents returned by Kaji tools as enabled and installed. Never assume Codex, Claude Code, or OpenCode are available.",
		"Use kaji_subagent for delegated coding work. Treat each independent fix or feature as a separate subagent assignment with a clear title.",
		"For each implementation assignment, call kaji_subagent action=plan before kaji_choose_agent. Pass assignmentID to kaji_choose_agent after planning.",
		"If kaji_subagent action=plan returns requiresIsolation, ask the user or choose isolatedWorktree before selecting a provider.",
		"Before calling kaji_subagent action=spawn or action=replace, call kaji_choose_agent for that specific task/project. Kaji will ask the user in native steps. Use the exact provider and model returned by the user.",
		"For requests with multiple independent fixes/features, even in the same project, split them into separate concrete tasks and call kaji_choose_agent separately for each task before spawning.",
		"For multi-project requests, identify each project-specific task first, then call kaji_choose_agent separately for each task/project before spawning.",
		"If you run multiple implementation assignments in parallel for the same project, set isolation=isolatedWorktree on each kaji_subagent spawn/replace. Use sharedWorktree only for sequential work or read-only investigation.",
		"The kaji_choose_agent answer is newline-delimited key=value text. If it includes mode=continue and assignmentID, use kaji_subagent action=send with that assignmentID. If it includes mode=replacement, use kaji_subagent action=replace with that assignmentID plus provider/model. Otherwise use kaji_subagent action=spawn.",
		"Do not spawn multiple child agents for the same concrete task. For independent subtasks, spawn separate child agents and supervise each run.",
		"When a follow-up should continue an existing child run, choose the continue option from kaji_choose_agent and use kaji_subagent action=send instead of spawning.",
		"When you spawn child agents, supervise them explicitly: observe, reason, sleep briefly if still running, then observe again.",
		"Use kaji_subagent action=wait and action=result instead of manual polling loops.",
		"Use kaji_subagent terminalOutput when finalSummary is absent or you need to inspect what is visible in the child terminal.",
		"Do not claim a child agent is done until kaji_subagent action=result reports a completed assignment with a meaningful final summary, terminal output, or changed files.",
		"Be concise and honest about what has or has not been executed.",
	].join("\n");
}

function graphSystemPrompt() {
	return [
		"You are Kaji's CodeGraph agent.",
		"You have scoped filesystem and shell tools for one Kaji project. Use those tools directly.",
		"Do not choose or spawn Codex, Claude Code, OpenCode, Pi, or any other coding-agent CLI.",
		"Do not call Kaji orchestration tools; they are intentionally unavailable in this mode.",
		"Read the Graphify skill file path from the user prompt when it exists and follow it as a plain instruction document.",
		"Do not rely on /graphify being installed as a slash command.",
		"Run all temporary Graphify work inside the Kaji work directory from the user prompt.",
		"When invoking Graphify's CLI or Python module, pass --out with the Kaji work directory and keep GRAPHIFY_OUT on that work directory's graphify-out path.",
		"Never invoke Graphify with its default output path because that writes graphify-out into the target project.",
		"Keep the target project untouched. Do not create or edit AGENTS.md, CLAUDE.md, graphify-out, or hook files inside the target project.",
		"After Graphify outputs are ready, run the Kaji finalizer command exactly as provided.",
		"Be concise and report what completed or failed.",
	].join("\n");
}

function agentMode() {
	return process.env.KAJI_PARENT_AGENT_MODE ?? "parent";
}

function kajiProtocolToolName(name: string) {
	if (name === "kaji_list_projects") return "kaji.list_projects";
	if (name === "kaji_get_active_context") return "kaji.get_active_context";
	if (name === "kaji_list_coding_agents") return "kaji.list_coding_agents";
	if (name === "kaji_ask_user") return "kaji.ask_user";
	if (name === "kaji_choose_agent") return "kaji.choose_agent";
	if (name === "kaji_subagent") return "kaji.subagent";
	if (name === "kaji_open_project") return "kaji.open_project";
	if (name === "kaji_select_project") return "kaji.select_project";
	if (name === "kaji_select_worktree") return "kaji.select_worktree";
	if (name === "kaji_open_terminal") return "kaji.open_terminal";
	if (name === "kaji_open_split") return "kaji.open_split";
	if (name === "kaji_jump_to_agent") return "kaji.jump_to_agent";
	if (name === "kaji_create_worktree") return "kaji.create_worktree";
	if (name === "kaji_get_changed_files") return "kaji.get_changed_files";
	if (name === "kaji_open_diff") return "kaji.open_diff";
	if (name === "kaji_run_verification") return "kaji.run_verification";
	return name;
}

function stringifyResult(result: unknown) {
	if (typeof result === "string") return result;
	return JSON.stringify(result, null, 2);
}

function attachmentSummary(attachments: ProtocolAttachment[]) {
	if (attachments.length === 0) return "";
	return [
		"Attached files:",
		...attachments.map(
			(attachment) => `- ${attachment.name} (${attachment.kind}, ${attachment.mimeType}) at ${attachment.path}`,
		),
	].join("\n");
}

function imageContent(attachment: ProtocolAttachment): ImageContent | undefined {
	if (attachment.kind !== "image") return undefined;
	try {
		return {
			type: "image",
			data: attachment.data ?? readFileSync(attachment.path).toString("base64"),
			mimeType: attachment.mimeType,
		};
	} catch {
		return undefined;
	}
}

function promptContent(message: ProtocolMessage): Array<TextContent | ImageContent> {
	const prompt = message.prompt?.trim() || "Please review the attached files.";
	const attachments = message.attachments ?? [];
	const summary = attachmentSummary(attachments);
	const content: Array<TextContent | ImageContent> = [
		{ type: "text", text: summary ? `${prompt}\n\n${summary}` : prompt },
	];
	for (const attachment of attachments) {
		const image = imageContent(attachment);
		if (image) content.push(image);
	}
	return content;
}

function callKajiTool(name: string, args: Record<string, unknown>, context: RuntimeContext): Promise<unknown> {
	const id = createID("tool");
	const promise = new Promise<unknown>((resolve, reject) => pendingTools.set(id, { resolve, reject }));
	send({ type: "tool_call", id, taskID: context.taskID, name: kajiProtocolToolName(name), arguments: args });
	return promise;
}

function tool(
	name: string,
	description: string,
	parameters: ReturnType<typeof Type.Object>,
	context: RuntimeContext,
): AgentTool {
	return {
		name,
		label: name,
		description,
		parameters,
		execute: async (_toolCallId, params, signal): Promise<AgentToolResult<unknown>> => {
			if (signal?.aborted) throw new Error("Tool call aborted");
			const result = await callKajiTool(name, params as Record<string, unknown>, context);
			return { content: [{ type: "text", text: stringifyResult(result) }], details: result };
		},
	};
}

function localTool(
	name: string,
	description: string,
	parameters: ReturnType<typeof Type.Object>,
	execute: (params: Record<string, unknown>, signal?: AbortSignal) => Promise<unknown> | unknown,
): AgentTool {
	return {
		name,
		label: name,
		description,
		parameters,
		execute: async (_toolCallId, params, signal): Promise<AgentToolResult<unknown>> => {
			if (signal?.aborted) throw new Error("Tool call aborted");
			const result = await execute(params as Record<string, unknown>, signal);
			return { content: [{ type: "text", text: stringifyResult(result) }], details: result };
		},
	};
}

function envRoots(name: string): string[] {
	const value = process.env[name];
	if (!value) return [];
	try {
		const parsed = JSON.parse(value);
		if (Array.isArray(parsed)) return parsed.map((item) => String(item)).filter(Boolean).map((item) => resolve(item));
	} catch {
		return value.split(":").map((item) => item.trim()).filter(Boolean).map((item) => resolve(item));
	}
	return [];
}

function readRoots() {
	return envRoots("KAJI_GRAPH_READ_ROOTS");
}

function writeRoots() {
	return envRoots("KAJI_GRAPH_WRITE_ROOTS");
}

function shellRoots() {
	return envRoots("KAJI_GRAPH_SHELL_ROOTS");
}

function normalizePath(path: unknown) {
	if (typeof path !== "string" || !path.trim()) throw new Error("path is required");
	return resolve(path);
}

function isWithin(path: string, roots: string[]) {
	const normalized = resolve(path);
	return roots.some((root) => normalized === root || normalized.startsWith(`${root}${sep}`));
}

function requireWithin(path: string, roots: string[], label: string) {
	if (roots.length === 0 || !isWithin(path, roots)) throw new Error(`${path} is outside allowed ${label} roots`);
	return path;
}

function existingPath(path: string) {
	try {
		return realpathSync(path);
	} catch {
		return path;
	}
}

function truncate(text: string, maxBytes: number) {
	if (Buffer.byteLength(text, "utf8") <= maxBytes) return { text, truncated: false };
	const buffer = Buffer.from(text, "utf8").subarray(0, maxBytes);
	return { text: buffer.toString("utf8"), truncated: true };
}

function graphTools(): AgentTool[] {
	return [
		localTool(
			"graph_list_files",
			"List files below an allowed read root. Use this to inspect project structure without printing huge trees.",
			Type.Object({
				path: Type.String(),
				limit: Type.Optional(Type.String()),
				maxDepth: Type.Optional(Type.String()),
			}),
			(params) => listFiles(params),
		),
		localTool(
			"graph_read_file",
			"Read a UTF-8 text file from an allowed read root.",
			Type.Object({
				path: Type.String(),
				maxBytes: Type.Optional(Type.String()),
			}),
			(params) => readFile(params),
		),
		localTool(
			"graph_write_file",
			"Write a UTF-8 text file inside an allowed write root.",
			Type.Object({
				path: Type.String(),
				content: Type.String(),
			}),
			(params) => writeFile(params),
		),
		localTool(
			"graph_shell",
			"Run a shell command in an allowed shell root. Use for Graphify Python/CLI and the finalizer.",
			Type.Object({
				command: Type.String(),
				cwd: Type.String(),
				timeoutSeconds: Type.Optional(Type.String()),
				maxBytes: Type.Optional(Type.String()),
			}),
			(params, signal) => runShell(params, signal),
		),
	];
}

function listFiles(params: Record<string, unknown>) {
	const root = requireWithin(existingPath(normalizePath(params.path)), readRoots(), "read");
	const limit = Math.max(1, Math.min(Number(params.limit ?? 400), 2000));
	const maxDepth = Math.max(0, Math.min(Number(params.maxDepth ?? 4), 12));
	const files: string[] = [];
	const walk = (dir: string, depth: number) => {
		if (files.length >= limit || depth > maxDepth) return;
		for (const entry of readdirSync(dir, { withFileTypes: true })) {
			if (files.length >= limit) return;
			if (entry.name === ".git" || entry.name === "node_modules" || entry.name === ".kaji") continue;
			const full = join(dir, entry.name);
			const relative = full.slice(root.length + 1);
			files.push(entry.isDirectory() ? `${relative}/` : relative);
			if (entry.isDirectory()) walk(full, depth + 1);
		}
	};
	walk(root, 0);
	return { root, files, truncated: files.length >= limit };
}

function readFile(params: Record<string, unknown>) {
	const path = requireWithin(existingPath(normalizePath(params.path)), readRoots(), "read");
	const maxBytes = Math.max(1, Math.min(Number(params.maxBytes ?? 120000), 500000));
	const { text, truncated } = truncate(readFileSync(path, "utf8"), maxBytes);
	return { path, text, truncated };
}

function writeFile(params: Record<string, unknown>) {
	const path = requireWithin(normalizePath(params.path), writeRoots(), "write");
	const content = typeof params.content === "string" ? params.content : "";
	mkdirSync(dirname(path), { recursive: true });
	writeFileSync(path, content, "utf8");
	return { path, bytes: Buffer.byteLength(content, "utf8") };
}

function blockedGraphifyCommand(command: string) {
	if (agentMode() !== "kajicodegraph") return undefined;
	if (/\s--out(?:\s|=)/.test(` ${command} `)) return undefined;
	const invokesGraphify =
		/(^|[;&|]\s*)graphify(?=$|[\s;&|])/.test(command) ||
		/(^|[\s;&|])-m\s+graphify(?=$|[\s;&|])/.test(command);
	if (!invokesGraphify) return undefined;
	const work = process.env.KAJI_GRAPH_WORK_DIR ?? "the Kaji work directory";
	return [
		"KajiCodeGraph blocked Graphify's default output path.",
		`Run it with --out ${work} and GRAPHIFY_OUT=${work}/graphify-out.`,
	].join(" ");
}

async function runShell(params: Record<string, unknown>, signal?: AbortSignal) {
	const command = typeof params.command === "string" ? params.command : "";
	if (!command.trim()) throw new Error("command is required");
	const cwd = requireWithin(existingPath(normalizePath(params.cwd)), shellRoots(), "shell");
	const blocked = blockedGraphifyCommand(command);
	if (blocked) return { cwd, exitCode: 2, stdout: "", stderr: blocked, truncated: false };
	const timeout = Math.max(1000, Math.min(Number(params.timeoutSeconds ?? 600) * 1000, 3600000));
	const maxBytes = Math.max(1000, Math.min(Number(params.maxBytes ?? 24000), 200000));
	const result = await execFileAsync("/bin/zsh", ["-lc", command], {
		cwd,
		timeout,
		signal,
		maxBuffer: Math.max(maxBytes * 2, 1024 * 1024),
		env: process.env,
	}).then(
		(value) => ({ stdout: value.stdout, stderr: value.stderr, exitCode: 0 }),
		(error) => ({ stdout: error.stdout ?? "", stderr: error.stderr ?? error.message, exitCode: error.code ?? 1 }),
	);
	const stdout = truncate(String(result.stdout), maxBytes);
	const stderr = truncate(String(result.stderr), maxBytes);
	return { cwd, exitCode: result.exitCode, stdout: stdout.text, stderr: stderr.text, truncated: stdout.truncated || stderr.truncated };
}

function kajiTools(context: RuntimeContext): AgentTool[] {
	return [
		tool("kaji_list_projects", "List projects available in Kaji.", Type.Object({}), context),
		tool(
			"kaji_get_active_context",
			"Get Kaji's active project, worktrees, and workspace context.",
			Type.Object({}),
			context,
		),
		tool(
			"kaji_list_coding_agents",
			"List enabled and installed coding agents with available model choices. Use this before planning delegation.",
			Type.Object({}),
			context,
		),
		tool(
			"kaji_ask_user",
			"Ask the user one concise question when required information is missing.",
			Type.Object({ question: Type.String() }),
			context,
		),
		tool(
			"kaji_choose_agent",
			"Ask the user whether to continue an existing child run or choose a coding agent/model for one specific task/project. Call once per independent task before spawning.",
			Type.Object({ task: Type.String(), project: Type.Optional(Type.String()) }),
			context,
		),
		tool(
			"kaji_subagent",
			"Manage Kaji subagent assignments. Use spawn for new work, replace for incomplete/stale work, send for continuing an assignment, status/result/wait for supervision, and stop to interrupt. Status/result/wait include terminalOutput when Kaji can read the child terminal screen.",
			Type.Object({
				action: Type.String(),
				assignmentID: Type.Optional(Type.String()),
				title: Type.Optional(Type.String()),
				prompt: Type.Optional(Type.String()),
				project: Type.Optional(Type.String()),
				provider: Type.Optional(Type.String()),
				model: Type.Optional(Type.String()),
				isolation: Type.Optional(Type.String()),
				timeoutSeconds: Type.Optional(Type.String()),
			}),
			context,
		),
		tool(
			"kaji_open_project",
			"Open and select a Kaji project by id, name, or path.",
			Type.Object({ project: Type.Optional(Type.String()), worktree: Type.Optional(Type.String()) }),
			context,
		),
		tool(
			"kaji_select_project",
			"Select a Kaji project by id, name, or path without spawning an agent.",
			Type.Object({ project: Type.Optional(Type.String()), worktree: Type.Optional(Type.String()) }),
			context,
		),
		tool(
			"kaji_select_worktree",
			"Select a worktree by id, name, path, or branch for the active or named project.",
			Type.Object({ project: Type.Optional(Type.String()), worktree: Type.Optional(Type.String()) }),
			context,
		),
		tool(
			"kaji_open_terminal",
			"Open a native Kaji terminal tab. Optional command runs in the selected project/worktree.",
			Type.Object({
				project: Type.Optional(Type.String()),
				worktree: Type.Optional(Type.String()),
				title: Type.Optional(Type.String()),
				command: Type.Optional(Type.String()),
			}),
			context,
		),
		tool(
			"kaji_open_split",
			"Open a native Kaji split. Optional command runs in the selected project/worktree. Direction may be horizontal or vertical for empty splits.",
			Type.Object({
				project: Type.Optional(Type.String()),
				worktree: Type.Optional(Type.String()),
				title: Type.Optional(Type.String()),
				command: Type.Optional(Type.String()),
				direction: Type.Optional(Type.String()),
			}),
			context,
		),
		tool(
			"kaji_jump_to_agent",
			"Navigate Kaji to a child agent run by runID.",
			Type.Object({ runID: Type.String() }),
			context,
		),
		tool(
			"kaji_create_worktree",
			"Create and select an isolated Git worktree for a project. By default creates a new branch; pass createBranch false to use an existing branch.",
			Type.Object({
				project: Type.Optional(Type.String()),
				name: Type.String(),
				branch: Type.Optional(Type.String()),
				createBranch: Type.Optional(Type.String()),
			}),
			context,
		),
		tool(
			"kaji_get_changed_files",
			"Get changed files for a runID or selected project/worktree. If runID is provided, Kaji attaches the snapshot to that run.",
			Type.Object({
				runID: Type.Optional(Type.String()),
				project: Type.Optional(Type.String()),
				worktree: Type.Optional(Type.String()),
			}),
			context,
		),
		tool(
			"kaji_open_diff",
			"Open Kaji's native diff viewer for a file. Prefer passing runID plus path when reviewing child-agent output.",
			Type.Object({
				runID: Type.Optional(Type.String()),
				project: Type.Optional(Type.String()),
				worktree: Type.Optional(Type.String()),
				path: Type.Optional(Type.String()),
				staged: Type.Optional(Type.String()),
			}),
			context,
		),
		tool(
			"kaji_run_verification",
			"Run the configured verification command for a tracked child agent run.",
			Type.Object({ runID: Type.String() }),
			context,
		),
	];
}

function handleAgentEvent(event: AgentEvent, context: RuntimeContext) {
	if (event.type === "message_update") {
		const streamEvent = event.assistantMessageEvent;
		if (streamEvent.type === "text_delta")
			send({ type: "assistant_delta", taskID: context.taskID, message: streamEvent.delta });
		if (streamEvent.type === "thinking_delta")
			send({ type: "thinking_delta", taskID: context.taskID, message: streamEvent.delta });
		if (streamEvent.type === "thinking_end") send({ type: "thinking_end", taskID: context.taskID });
		if (streamEvent.type === "toolcall_end")
			send({
				type: "task_event",
				taskID: context.taskID,
				event: "tool.requested",
				message: streamEvent.toolCall.name,
			});
	}
	if (event.type === "tool_execution_start")
		send({ type: "task_event", taskID: context.taskID, event: "tool.started", message: event.toolName });
	if (event.type === "tool_execution_end")
		send({ type: "task_event", taskID: context.taskID, event: "tool.completed", message: event.toolName });
}

function createAgent(model: Model<Api>, context: RuntimeContext) {
	const agent = new Agent({
		initialState: {
			systemPrompt: systemPrompt(),
			model,
			thinkingLevel: selectedThinking(),
			tools: agentMode() === "kajicodegraph" ? graphTools() : kajiTools(context),
		},
		getApiKey: (provider) => resolveApiKey(provider),
		toolExecution: "sequential",
	});
	agent.subscribe((event) => handleAgentEvent(event, context));
	return agent;
}

async function runPrompt(message: ProtocolMessage) {
	const context: RuntimeContext = { taskID: message.taskID, sessionID: message.taskID ?? "default" };
	const model = selectedModel();
	if (!model) {
		send({ type: "error", taskID: message.taskID, message: "Parent model was not found." });
		return;
	}
	if (!(await resolveApiKey(model.provider))) {
		send({ type: "error", taskID: message.taskID, message: `Missing API key for ${model.provider}.` });
		return;
	}

	send({
		type: "task_event",
		taskID: message.taskID,
		event: "task.planning",
		message: `Using ${model.provider}/${model.id}.`,
	});
	const agent = sessions.get(context.sessionID) ?? createAgent(model, context);
	sessions.set(context.sessionID, agent);
	await agent.prompt({ role: "user", content: promptContent(message), timestamp: Date.now() });
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
		if (message.type === "user_prompt") {
			promptQueue = promptQueue
				.then(() => runPrompt(message))
				.catch((error) =>
					send({
						type: "error",
						taskID: message.taskID,
						message: error instanceof Error ? error.message : String(error),
					}),
				);
		}
		if (message.type === "tool_result") handleToolResult(message);
	} catch (error) {
		send({ type: "error", message: error instanceof Error ? error.message : String(error) });
	}
});

send({ type: "heartbeat", message: "kaji-pi-parent-agent-ready" });
