export type PreferredEditTool = "edit" | "patch" | "ast_edit" | "compound_edit";
export type ModelReasoningStyle = "none" | "low" | "medium" | "high";

export interface ModelHarnessProfile {
	modelPattern: string;
	preferredEditTool: PreferredEditTool;
	maxParallelToolCalls?: number;
	toolDescriptionBudget?: number;
	forceToolChoiceSupported: boolean;
	reasoningStyle: ModelReasoningStyle;
}

export const MODEL_HARNESS_PROFILES: readonly ModelHarnessProfile[] = [
	{
		modelPattern: "gpt-5*",
		preferredEditTool: "edit",
		maxParallelToolCalls: 8,
		toolDescriptionBudget: 12000,
		forceToolChoiceSupported: true,
		reasoningStyle: "high",
	},
	{
		modelPattern: "claude-*",
		preferredEditTool: "edit",
		maxParallelToolCalls: 6,
		toolDescriptionBudget: 10000,
		forceToolChoiceSupported: true,
		reasoningStyle: "high",
	},
	{
		modelPattern: "gemini-*",
		preferredEditTool: "patch",
		maxParallelToolCalls: 4,
		toolDescriptionBudget: 8000,
		forceToolChoiceSupported: true,
		reasoningStyle: "medium",
	},
	{
		modelPattern: "local/*",
		preferredEditTool: "compound_edit",
		maxParallelToolCalls: 1,
		toolDescriptionBudget: 4000,
		forceToolChoiceSupported: false,
		reasoningStyle: "low",
	},
];

const DEFAULT_MODEL_HARNESS_PROFILE: ModelHarnessProfile = {
	modelPattern: "*",
	preferredEditTool: "edit",
	maxParallelToolCalls: 4,
	toolDescriptionBudget: 8000,
	forceToolChoiceSupported: true,
	reasoningStyle: "medium",
};

export function resolveModelHarnessProfile(model: string | undefined): ModelHarnessProfile {
	const value = model?.trim().toLowerCase() ?? "";
	if (!value) return DEFAULT_MODEL_HARNESS_PROFILE;
	return MODEL_HARNESS_PROFILES.find(profile => glob(profile.modelPattern.toLowerCase(), value)) ?? DEFAULT_MODEL_HARNESS_PROFILE;
}

function glob(pattern: string, value: string): boolean {
	if (pattern === "*" || pattern === value) return true;
	const escaped = pattern.replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*");
	return new RegExp(`^${escaped}$`).test(value);
}
