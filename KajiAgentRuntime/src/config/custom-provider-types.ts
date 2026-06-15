import type { AzureOpenAIDiscoveryAccount } from "./azure-openai-deployment-discovery";
import type { CustomProviderApiKeySource } from "./custom-provider-secrets";
import type { ModelsConfig } from "./models-config-schema";

export type ProviderConfig = NonNullable<ModelsConfig["providers"]>[string];
export type ProviderModel = NonNullable<ProviderConfig["models"]>[number];

export interface CustomProviderModelInput {
	id: string;
	name?: string;
	reasoning?: boolean;
	input?: Array<"text" | "image">;
	contextWindow?: number;
	maxTokens?: number;
}

export interface CustomProviderInput {
	id: string;
	baseUrl?: string;
	apiKey?: string;
	api?: ProviderConfig["api"];
	auth?: ProviderConfig["auth"];
	discovery?: ProviderConfig["discovery"];
	headers?: Record<string, string>;
	disableStrictTools?: boolean;
	models?: CustomProviderModelInput[];
}

export interface CustomProviderSummary extends CustomProviderInput {
	isOverrideOnly: boolean;
	modelCount: number;
	apiKeyConfigured: boolean;
	apiKeySource: CustomProviderApiKeySource;
	apiKeyResolved: boolean;
	apiKeyName?: string;
}

export interface CustomProvidersResult {
	path: string;
	providers: CustomProviderSummary[];
}

export interface CustomProviderAutoMatchResult {
	models: CustomProviderModelInput[];
	account?: AzureOpenAIDiscoveryAccount;
}
