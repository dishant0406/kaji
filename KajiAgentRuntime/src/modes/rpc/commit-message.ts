import type { ThinkingLevel } from "@oh-my-pi/pi-agent-core";
import { completeSimple, type Api, type Model } from "@oh-my-pi/pi-ai";
import { resolvePrimaryModel } from "../../commit/model-selection";
import type { AgentSession } from "../../session/agent-session";
import { toReasoningEffort } from "../../thinking";

const SYSTEM_PROMPT = [
	"You are Kaji's Git commit message generator.",
	"Return only the final commit message text.",
	"Do not use markdown fences or explanations.",
].join("\n");

const MAX_TOKENS = 900;
const REASONING_MAX_TOKENS = 1400;

export interface RpcCommitMessageRequest {
	provider?: string;
	modelId?: string;
	promptMessage: string;
	thinkingLevel?: ThinkingLevel;
}

export interface RpcCommitMessageResult {
	message: string;
	model: Model<Api>;
}

export async function generateRpcCommitMessage(
	session: AgentSession,
	request: RpcCommitMessageRequest,
): Promise<RpcCommitMessageResult> {
	const promptMessage = request.promptMessage.trim();
	if (!promptMessage) throw new Error("Commit prompt is empty");

	const resolved = await resolveModel(session, request);
	const maxTokens = resolved.model.reasoning ? REASONING_MAX_TOKENS : MAX_TOKENS;
	const response = await completeSimple(
		resolved.model,
		{
			systemPrompt: [SYSTEM_PROMPT],
			messages: [{ role: "user", content: promptMessage, timestamp: Date.now() }],
		},
		{
			apiKey: resolved.apiKey,
			maxTokens,
			reasoning: toReasoningEffort(request.thinkingLevel ?? resolved.thinkingLevel),
		},
	);

	if (response.stopReason === "error") {
		throw new Error(response.errorMessage || "Commit message generation failed");
	}

	const message = cleanMessage(
		response.content.map(part => (part.type === "text" ? part.text : "")).join(""),
	);
	if (!message) throw new Error("Commit message generation returned an empty response");
	return { message, model: resolved.model };
}

async function resolveModel(session: AgentSession, request: RpcCommitMessageRequest) {
	const provider = request.provider?.trim();
	const modelId = request.modelId?.trim();
	if (provider || modelId) {
		if (!provider || !modelId) throw new Error("Both provider and modelId are required");
		const model = session.getAvailableModels().find(candidate => candidate.provider === provider && candidate.id === modelId);
		if (!model) throw new Error(`Model not found: ${provider}/${modelId}`);
		const apiKey = await session.modelRegistry.getApiKey(model, session.sessionId);
		if (!apiKey) throw new Error(`No API key available for model ${provider}/${modelId}`);
		return { model, apiKey, thinkingLevel: undefined };
	}
	return resolvePrimaryModel(undefined, session.settings, {
		getAvailable: () => session.getAvailableModels(),
		getApiKey: model => session.modelRegistry.getApiKey(model, session.sessionId),
		getCanonicalVariants: selector => session.modelRegistry.getCanonicalVariants(selector),
	});
}

function cleanMessage(value: string): string {
	let message = value.trim();
	message = message.replace(/^```(?:\w+)?\s*/, "").replace(/\s*```$/, "").trim();
	if (isWrapped(message, "\"")) message = message.slice(1, -1).trim();
	if (isWrapped(message, "'")) message = message.slice(1, -1).trim();
	if (isWrapped(message, "`")) message = message.slice(1, -1).trim();
	return message;
}

function isWrapped(value: string, quote: string): boolean {
	return value.length >= 2 && value.startsWith(quote) && value.endsWith(quote);
}
