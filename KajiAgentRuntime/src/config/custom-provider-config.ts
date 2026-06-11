import * as fs from "node:fs/promises";
import * as path from "node:path";
import { YAML } from "bun";
import { isEnoent } from "@oh-my-pi/pi-utils";
import { discoverAzureOpenAIDeployments, type AzureOpenAIDiscoveryAccount } from "./azure-openai-deployment-discovery";
import { cleanValue, normalizeHeaders, normalizeOptional, normalizeRequired, uniqueInput, validateProviderId } from "./custom-provider-config-normalize";
import { ModelsConfigFile, validateModelsConfig } from "./model-registry";
import { type ModelsConfig, ModelsConfigSchema } from "./models-config-schema";
import { withFileLock } from "./file-lock";

type ProviderConfig = NonNullable<ModelsConfig["providers"]>[string];
type ProviderModel = NonNullable<ProviderConfig["models"]>[number];

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
}

export interface CustomProvidersResult {
	path: string;
	providers: CustomProviderSummary[];
}

export interface CustomProviderAutoMatchResult {
	models: CustomProviderModelInput[];
	account?: AzureOpenAIDiscoveryAccount;
}

export async function listCustomProviders(modelsPath = ModelsConfigFile.path()): Promise<CustomProvidersResult> {
	const config = await readConfig(modelsPath);
	return {
		path: modelsPath,
		providers: Object.entries(config.providers ?? {})
			.map(([id, provider]) => summarizeProvider(id, provider))
			.sort((a, b) => a.id.localeCompare(b.id)),
	};
}

export async function saveCustomProvider(input: CustomProviderInput, modelsPath = ModelsConfigFile.path()): Promise<CustomProvidersResult> {
	return withFileLock(modelsPath, async () => {
		const current = await readConfig(modelsPath);
		const providers = { ...(current.providers ?? {}) };
		const id = normalizeRequired(input.id, "Provider ID");
		validateProviderId(id);
		providers[id] = buildProviderConfig(input, providers[id]);
		await writeConfig({ ...current, providers }, modelsPath);
		return listCustomProviders(modelsPath);
	});
}

export async function deleteCustomProvider(id: string, modelsPath = ModelsConfigFile.path()): Promise<CustomProvidersResult> {
	return withFileLock(modelsPath, async () => {
		const providerId = normalizeRequired(id, "Provider ID");
		validateProviderId(providerId);
		const current = await readConfig(modelsPath);
		const providers = { ...(current.providers ?? {}) };
		delete providers[providerId];
		const next = { ...current, providers: Object.keys(providers).length > 0 ? providers : undefined };
		await writeConfig(next, modelsPath);
		return listCustomProviders(modelsPath);
	});
}

export async function previewCustomProviderModels(input: CustomProviderInput): Promise<CustomProviderAutoMatchResult> {
	const id = normalizeRequired(input.id, "Provider ID");
	validateProviderId(id);
	if (input.discovery?.type !== "azure-openai-deployments") {
		throw new Error("Auto Match Models currently supports Azure OpenAI deployments discovery.");
	}
	if (input.api !== "azure-openai-responses") {
		throw new Error("Azure OpenAI deployment discovery requires Azure OpenAI Responses API.");
	}
	const result = await discoverAzureOpenAIDeployments({
		provider: id,
		api: input.api,
		baseUrl: input.baseUrl,
		headers: normalizeHeaders(input.headers),
		discovery: input.discovery,
	});
	return {
		account: result.account,
		models: result.models.map(model => ({
			id: model.id,
			name: model.name,
			reasoning: model.reasoning,
			input: model.input,
			contextWindow: normalizedTokenLimit(model.contextWindow),
			maxTokens: normalizedTokenLimit(model.maxTokens),
		})),
	};
}

async function readConfig(modelsPath: string): Promise<ModelsConfig> {
	try {
		const content = (await fs.readFile(modelsPath, "utf-8")).trim();
		if (!content) return {};
		const parsed = YAML.parse(content) ?? {};
		const result = ModelsConfigSchema.safeParse(parsed);
		if (!result.success) throw new Error(result.error.issues.map(issue => `${issue.path.join(".") || "root"}: ${issue.message}`).join("; "));
		validateModelsConfig(result.data);
		return result.data;
	} catch (error) {
		if (isEnoent(error)) return {};
		throw error;
	}
}

async function writeConfig(config: ModelsConfig, modelsPath: string): Promise<void> {
	const result = ModelsConfigSchema.safeParse(cleanValue(config));
	if (!result.success) throw new Error(result.error.issues.map(issue => `${issue.path.join(".") || "root"}: ${issue.message}`).join("; "));
	validateModelsConfig(result.data);
	await fs.mkdir(path.dirname(modelsPath), { recursive: true });
	const tempPath = `${modelsPath}.${process.pid}.${Date.now()}.tmp`;
	await fs.writeFile(tempPath, YAML.stringify(result.data, null, 2));
	await fs.rename(tempPath, modelsPath);
}

function buildProviderConfig(input: CustomProviderInput, existing: ProviderConfig | undefined): ProviderConfig {
	const auth = input.auth ?? existing?.auth ?? "apiKey";
	const next: ProviderConfig = {
		...(existing ?? {}),
		baseUrl: normalizeOptional(input.baseUrl),
		apiKey: auth === "none" ? undefined : normalizeOptional(input.apiKey) ?? existing?.apiKey,
		api: input.api,
		auth,
		discovery: input.discovery,
		headers: normalizeHeaders(input.headers),
		disableStrictTools: input.disableStrictTools === true ? true : undefined,
		models: buildModels(input.models ?? [], existing?.models ?? []),
	};
	return cleanValue(next) as ProviderConfig;
}

function buildModels(inputs: CustomProviderModelInput[], existingModels: ProviderModel[]): ProviderModel[] | undefined {
	const existingById = new Map(existingModels.map(model => [model.id, model]));
	const models = inputs.map(input => {
		const id = normalizeRequired(input.id, "Model ID");
		const existing = existingById.get(id);
		const model: ProviderModel = {
			...(existing ?? {}),
			id,
			name: normalizeOptional(input.name),
			reasoning: input.reasoning,
			input: input.input && input.input.length > 0 ? uniqueInput(input.input) : existing?.input,
			contextWindow: input.contextWindow,
			maxTokens: input.maxTokens,
		};
		return cleanValue(model) as ProviderModel;
	});
	return models.length > 0 ? models : undefined;
}

function summarizeProvider(id: string, provider: ProviderConfig): CustomProviderSummary {
	return {
		id,
		baseUrl: provider.baseUrl,
		apiKey: provider.apiKey,
		api: provider.api,
		auth: provider.auth ?? "apiKey",
		discovery: provider.discovery,
		headers: provider.headers,
		disableStrictTools: provider.disableStrictTools,
		models: (provider.models ?? []).map(model => ({
			id: model.id,
			name: model.name,
			reasoning: model.reasoning,
			input: model.input,
			contextWindow: model.contextWindow,
			maxTokens: model.maxTokens,
		})),
		isOverrideOnly: !provider.models || provider.models.length === 0,
		modelCount: provider.models?.length ?? 0,
	};
}

function normalizedTokenLimit(value: number | undefined): number | undefined {
	if (!value || value <= 0 || value >= 9000000000000000) return undefined;
	return value;
}
