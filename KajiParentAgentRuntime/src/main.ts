import readline from "node:readline";
import type { Agent, AgentMessage } from "@earendil-works/pi-agent-core";
import type { TextContent } from "@earendil-works/pi-ai";
import { createAgent, promptContent, selectedModel } from "./agent.js";
import { resolveApiKey } from "./auth.js";
import type { PendingTool, ProtocolMessage, RuntimeContext } from "./protocol.js";
import { send, stringifyResult } from "./protocol.js";

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Number.POSITIVE_INFINITY });
const pendingTools = new Map<string, PendingTool>();
const sessions = new Map<string, Agent>();
let promptQueue = Promise.resolve();

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
	const agent = sessions.get(context.sessionID) ?? createAgent(model, context, pendingTools);
	sessions.set(context.sessionID, agent);
	await agent.prompt({ role: "user", content: promptContent(message), timestamp: Date.now() });
	send({ type: "final_response", taskID: message.taskID, message: lastAssistantText(agent) });
}

function lastAssistantText(agent: Agent) {
	const messages = [...agent.state.messages].reverse() as AgentMessage[];
	const assistant = messages.find((message) => message.role === "assistant");
	if (!assistant) return "";
	return assistant.content
		.filter((part): part is TextContent => part.type === "text")
		.map((part) => part.text)
		.join("")
		.trim();
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
