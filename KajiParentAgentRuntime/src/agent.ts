import { readFileSync } from "node:fs";
import {
	Agent,
	type AgentEvent,
	type ThinkingLevel,
} from "@earendil-works/pi-agent-core";
import {
	type Api,
	getModels,
	type ImageContent,
	type KnownProvider,
	type Model,
	type TextContent,
} from "@earendil-works/pi-ai";
import { resolveApiKey } from "./auth.js";
import { graphTools } from "./graph-tools.js";
import { kajiTools } from "./kaji-tools.js";
import { agentMode } from "./mode.js";
import type { PendingTool, ProtocolAttachment, ProtocolMessage, RuntimeContext } from "./protocol.js";
import { send } from "./protocol.js";
import { systemPrompt } from "./prompts.js";

export function selectedModel(): Model<Api> | undefined {
	const provider = process.env.KAJI_PARENT_PROVIDER ?? "anthropic";
	const modelID = process.env.KAJI_PARENT_MODEL ?? "claude-sonnet-4-5";
	return getModels(provider as KnownProvider).find((model) => model.id === modelID) as Model<Api> | undefined;
}

export function selectedThinking(): ThinkingLevel {
	const value = process.env.KAJI_PARENT_THINKING ?? "off";
	if (value === "minimal" || value === "low" || value === "medium" || value === "high" || value === "xhigh") {
		return value;
	}
	return "off";
}

export function promptContent(message: ProtocolMessage): Array<TextContent | ImageContent> {
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

export function createAgent(model: Model<Api>, context: RuntimeContext, pendingTools: Map<string, PendingTool>) {
	const agent = new Agent({
		initialState: {
			systemPrompt: systemPrompt(),
			model,
			thinkingLevel: selectedThinking(),
			tools: agentMode() === "kajicodegraph" ? graphTools() : kajiTools(context, pendingTools),
		},
		getApiKey: (provider) => resolveApiKey(provider),
		toolExecution: "sequential",
	});
	agent.subscribe((event) => handleAgentEvent(event, context));
	return agent;
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

function handleAgentEvent(event: AgentEvent, context: RuntimeContext) {
	if (event.type === "message_update") {
		const streamEvent = event.assistantMessageEvent;
		if (streamEvent.type === "text_delta") {
			send({ type: "assistant_delta", taskID: context.taskID, message: streamEvent.delta });
		}
		if (streamEvent.type === "thinking_delta") {
			send({ type: "thinking_delta", taskID: context.taskID, message: streamEvent.delta });
		}
		if (streamEvent.type === "thinking_end") send({ type: "thinking_end", taskID: context.taskID });
		if (streamEvent.type === "toolcall_end") {
			send({
				type: "task_event",
				taskID: context.taskID,
				event: "tool.requested",
				message: streamEvent.toolCall.name,
			});
		}
	}
	if (event.type === "tool_execution_start") {
		send({ type: "task_event", taskID: context.taskID, event: "tool.started", message: event.toolName });
	}
	if (event.type === "tool_execution_end") {
		send({ type: "task_event", taskID: context.taskID, event: "tool.completed", message: event.toolName });
	}
}
