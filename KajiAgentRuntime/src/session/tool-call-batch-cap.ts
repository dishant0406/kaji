import type { Model } from "@oh-my-pi/pi-ai";

export const ANTHROPIC_TOOL_CALL_BATCH_CAP = 4;
const CLAUDE_OPUS_4_8_MODEL_ID = /(?:^|[./_-])claude-opus-4[.-]8\b/i;

export function resolveToolCallBatchCapForModel(model: Model | undefined): number | undefined {
	if (!model) return undefined;
	return model.provider === "anthropic" && CLAUDE_OPUS_4_8_MODEL_ID.test(model.id)
		? ANTHROPIC_TOOL_CALL_BATCH_CAP
		: undefined;
}
