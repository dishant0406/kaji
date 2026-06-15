import * as fs from "node:fs/promises";
import { YAML } from "bun";
import { isEnoent } from "@oh-my-pi/pi-utils";
import { discoverAzureOpenAIDeployments, type AzureOpenAIDiscoveryAccount } from "./azure-openai-deployment-discovery";
import { DefaultAzureCliRunner, type AzureCliRunner } from "./azure-cli-runner";
import { normalizeRequired, validateProviderId } from "./custom-provider-config-normalize";
import { ModelsConfigFile } from "./model-registry";
import { type ModelsConfig, ModelsConfigSchema } from "./models-config-schema";
import { providerApiKeyStatus, resolveProviderApiKey, type CustomProviderApiKeyStatus } from "./custom-provider-secrets";
import type { CustomProviderInput, ProviderConfig } from "./custom-provider-types";

export interface CustomProviderValidationResult {
	providerId: string;
	ok: boolean;
	severity: "ok" | "warning" | "error";
	title: string;
	message: string;
	statusCode?: number;
	modelId?: string;
	account?: AzureOpenAIDiscoveryAccount;
	keyStatus: CustomProviderApiKeyStatus;
	keyMatchesAzureResource?: boolean;
}

export interface CustomProviderValidationOptions {
	modelsPath?: string;
	runner?: AzureCliRunner;
	fetch?: typeof fetch;
}

export async function validateCustomProviderConnection(
	input: CustomProviderInput,
	options: CustomProviderValidationOptions = {},
): Promise<CustomProviderValidationResult> {
	const providerId = normalizeRequired(input.id, "Provider ID");
	validateProviderId(providerId);
	const config = await mergedProviderConfig(input, providerId, options.modelsPath ?? ModelsConfigFile.path());
	if (config.api !== "azure-openai-responses") {
		throw new Error("Connection validation currently supports Azure OpenAI Responses providers.");
	}
	const keyStatus = providerApiKeyStatus(config.apiKey);
	const apiKey = resolveProviderApiKey(config.apiKey);
	if (!apiKey) return missingKeyResult(providerId, keyStatus);
	const discovery = await tryDiscoverAzureModels(providerId, config, options.runner ?? new DefaultAzureCliRunner());
	const modelId = firstModelId(input, config, discovery.models);
	if (!modelId) return errorResult(providerId, keyStatus, "No model to validate", "Auto-match or add one Azure deployment before validating.");
	const keyMatchesAzureResource = await compareAzureResourceKeys(apiKey, discovery.account, options.runner ?? new DefaultAzureCliRunner(), keyStatus);
	const result = await probeAzureResponses(config, apiKey, modelId, options.fetch ?? fetch);
	return {
		providerId,
		ok: result.ok,
		severity: result.ok ? "ok" : "error",
		title: result.ok ? "Azure connection verified" : "Azure connection failed",
		message: validationMessage(result, keyMatchesAzureResource, discovery.error),
		statusCode: result.status,
		modelId,
		account: discovery.account,
		keyStatus,
		keyMatchesAzureResource,
	};
}

async function mergedProviderConfig(input: CustomProviderInput, providerId: string, modelsPath: string): Promise<ProviderConfig> {
	const existing = (await readConfig(modelsPath)).providers?.[providerId];
	return {
		...(existing ?? {}),
		baseUrl: input.baseUrl?.trim() || existing?.baseUrl,
		apiKey: input.auth === "none" ? undefined : input.apiKey?.trim() || existing?.apiKey,
		api: input.api ?? existing?.api,
		auth: input.auth ?? existing?.auth ?? "apiKey",
		discovery: input.discovery ?? existing?.discovery,
		headers: input.headers ?? existing?.headers,
		models: input.models?.some(model => model.id.trim()) ? input.models : existing?.models,
	};
}

async function readConfig(modelsPath: string): Promise<ModelsConfig> {
	try {
		const content = (await fs.readFile(modelsPath, "utf-8")).trim();
		if (!content) return {};
		const parsed = YAML.parse(content) ?? {};
		const result = ModelsConfigSchema.safeParse(parsed);
		if (!result.success) return {};
		return result.data;
	} catch (error) {
		if (isEnoent(error)) return {};
		throw error;
	}
}

async function tryDiscoverAzureModels(providerId: string, config: ProviderConfig, runner: AzureCliRunner) {
	if (config.discovery?.type !== "azure-openai-deployments") return { models: [], account: undefined, error: undefined };
	try {
		const result = await discoverAzureOpenAIDeployments({
			provider: providerId,
			api: "azure-openai-responses",
			baseUrl: config.baseUrl,
			headers: config.headers,
			discovery: config.discovery,
		}, runner);
		return { models: result.models.map(model => model.id), account: result.account, error: undefined };
	} catch (error) {
		return { models: [], account: undefined, error: error instanceof Error ? error.message : String(error) };
	}
}

function firstModelId(input: CustomProviderInput, config: ProviderConfig, discoveredModels: string[]): string | undefined {
	return input.models?.find(model => model.id.trim())?.id.trim() ?? config.models?.find(model => model.id.trim())?.id.trim() ?? discoveredModels[0];
}

async function compareAzureResourceKeys(
	apiKey: string,
	account: AzureOpenAIDiscoveryAccount | undefined,
	runner: AzureCliRunner,
	keyStatus: CustomProviderApiKeyStatus,
): Promise<boolean | undefined> {
	if (!account || keyStatus.source !== "literal") return undefined;
	const args = ["cognitiveservices", "account", "keys", "list", "--resource-group", account.resourceGroup, "--name", account.name];
	if (account.subscription) args.push("--subscription", account.subscription);
	try {
		const keys = await runner.run(args);
		if (!keys || typeof keys !== "object") return undefined;
		const values = Object.values(keys).filter((value): value is string => typeof value === "string");
		return values.includes(apiKey);
	} catch {
		return undefined;
	}
}

async function probeAzureResponses(config: ProviderConfig, apiKey: string, modelId: string, fetchImpl: typeof fetch) {
	const response = await fetchImpl(`${normalizeAzureBaseUrl(config.baseUrl)}/responses?api-version=v1`, {
		method: "POST",
		headers: { "Content-Type": "application/json", "api-key": apiKey, ...(config.headers ?? {}) },
		body: JSON.stringify({ model: modelId, input: "Return ok.", max_output_tokens: 16, stream: false }),
	});
	const body = await response.text();
	return { ok: response.ok, status: response.status, error: extractErrorMessage(body) };
}

function normalizeAzureBaseUrl(baseUrl: string | undefined): string {
	const trimmed = baseUrl?.trim().replace(/\/+$/, "");
	if (!trimmed) throw new Error("Azure OpenAI base URL is required.");
	if (trimmed.endsWith("/openai/v1")) return trimmed;
	if (trimmed.endsWith("/openai")) return `${trimmed}/v1`;
	return `${trimmed}/openai/v1`;
}

function extractErrorMessage(body: string): string | undefined {
	try {
		const parsed = JSON.parse(body);
		return parsed?.error?.message ?? parsed?.message;
	} catch {
		return body.slice(0, 240) || undefined;
	}
}

function validationMessage(result: { ok: boolean; status: number; error?: string }, keyMatch: boolean | undefined, discoveryError?: string): string {
	if (result.ok) return discoveryError ? `Inference works. Azure discovery warning: ${discoveryError}` : "Inference works with the saved provider settings.";
	if (keyMatch === false) return "The saved literal API key does not match the current Azure resource keys. Replace it with a current key or save an environment variable that Kaji can read.";
	return result.error ?? `Azure returned HTTP ${result.status}.`;
}

function missingKeyResult(providerId: string, keyStatus: CustomProviderApiKeyStatus): CustomProviderValidationResult {
	return errorResult(providerId, keyStatus, "Azure API key is unavailable", keyStatus.name ? `${keyStatus.name} is not available to the Kaji Agent runtime.` : "Save an API key or environment variable name.");
}

function errorResult(providerId: string, keyStatus: CustomProviderApiKeyStatus, title: string, message: string): CustomProviderValidationResult {
	return { providerId, ok: false, severity: "error", title, message, keyStatus };
}
