import { isRecord } from "@oh-my-pi/pi-utils";
import {
	type Api,
	enrichModelThinking,
	type Model,
	UNK_CONTEXT_WINDOW,
	UNK_MAX_TOKENS,
} from "@oh-my-pi/pi-ai";
import type { ProviderDiscovery } from "./models-config-schema";
import { DefaultAzureCliRunner, type AzureCliRunner } from "./azure-cli-runner";

export interface AzureOpenAIDiscoveryRequest {
	provider: string;
	api: Api;
	baseUrl?: string;
	headers?: Record<string, string>;
	discovery: ProviderDiscovery;
}

export interface AzureOpenAIDiscoveryAccount {
	name: string;
	resourceGroup: string;
	endpoint?: string;
	subscription?: string;
}

export interface AzureOpenAIDiscoveryResult {
	account: AzureOpenAIDiscoveryAccount;
	models: Model<"azure-openai-responses">[];
}

interface AzureAccountPayload {
	name?: unknown;
	resourceGroup?: unknown;
	properties?: { endpoint?: unknown };
}

interface AzureDeploymentPayload {
	name?: unknown;
	properties?: {
		capabilities?: Record<string, unknown>;
		model?: { name?: unknown; version?: unknown };
		provisioningState?: unknown;
	};
}

export async function discoverAzureOpenAIDeployments(
	request: AzureOpenAIDiscoveryRequest,
	runner: AzureCliRunner = new DefaultAzureCliRunner(),
): Promise<AzureOpenAIDiscoveryResult> {
	if (request.api !== "azure-openai-responses") {
		throw new Error("Azure OpenAI deployment discovery requires api: azure-openai-responses.");
	}
	const account = await resolveAzureAccount(request, runner);
	const args = ["cognitiveservices", "account", "deployment", "list", "--resource-group", account.resourceGroup, "--name", account.name];
	if (account.subscription) args.push("--subscription", account.subscription);
	const deployments = asArray(await runner.run(args));
	const models = deployments.flatMap(item => deploymentToModel(item, request));
	return { account, models };
}

async function resolveAzureAccount(
	request: AzureOpenAIDiscoveryRequest,
	runner: AzureCliRunner,
): Promise<AzureOpenAIDiscoveryAccount> {
	const accountName = request.discovery.accountName?.trim() || resourceNameFromBaseUrl(request.baseUrl);
	const resourceGroup = request.discovery.resourceGroup?.trim();
	const subscription = request.discovery.subscription?.trim();
	if (accountName && resourceGroup) return { name: accountName, resourceGroup, subscription, endpoint: request.baseUrl };
	const args = ["cognitiveservices", "account", "list"];
	if (subscription) args.push("--subscription", subscription);
	const accounts = asArray(await runner.run(args));
	const match = accounts.map(asAzureAccount).find(account => matchesAzureAccount(account, accountName, request.baseUrl));
	if (!match) throw new Error(`Azure OpenAI account not found for ${request.baseUrl || accountName || "provider"}.`);
	return { ...match, subscription };
}

function deploymentToModel(value: unknown, request: AzureOpenAIDiscoveryRequest): Model<"azure-openai-responses">[] {
	const deployment = asAzureDeployment(value);
	if (!deployment) return [];
	const capabilities = deployment.properties?.capabilities ?? {};
	if (deployment.properties?.provisioningState !== "Succeeded") return [];
	if (request.discovery.includeNonResponses !== true && capabilities.responses !== "true") return [];
	const modelName = stringValue(deployment.properties?.model?.name) ?? deployment.name;
	if (isUnsupportedAgentModel(modelName, capabilities)) return [];
	const base = enrichModelThinking({
		id: modelName,
		name: displayName(deployment.name, modelName),
		api: "azure-openai-responses",
		provider: request.provider,
		baseUrl: normalizeAzureBaseUrl(request.baseUrl),
		reasoning: isReasoningModel(modelName),
		input: inputModalities(modelName, capabilities),
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
		contextWindow: numberCapability(capabilities.maxContextToken) ?? UNK_CONTEXT_WINDOW,
		maxTokens: numberCapability(capabilities.maxOutputToken) ?? UNK_MAX_TOKENS,
		headers: request.headers,
	});
	return [{ ...base, id: deployment.name, name: displayName(deployment.name, modelName) }];
}

function asArray(value: unknown): unknown[] {
	if (Array.isArray(value)) return value;
	if (isRecord(value) && Array.isArray(value.value)) return value.value;
	return [];
}

function asAzureAccount(value: unknown): AzureOpenAIDiscoveryAccount | undefined {
	if (!isRecord(value)) return undefined;
	const payload = value as AzureAccountPayload;
	const name = stringValue(payload.name);
	const resourceGroup = stringValue(payload.resourceGroup);
	if (!name || !resourceGroup) return undefined;
	return { name, resourceGroup, endpoint: stringValue(payload.properties?.endpoint) };
}

function asAzureDeployment(value: unknown): (AzureDeploymentPayload & { name: string }) | undefined {
	if (!isRecord(value)) return undefined;
	const payload = value as AzureDeploymentPayload;
	const name = stringValue(payload.name);
	if (!name) return undefined;
	return { ...payload, name };
}

function matchesAzureAccount(account: AzureOpenAIDiscoveryAccount | undefined, name: string | undefined, baseUrl: string | undefined): boolean {
	if (!account) return false;
	if (name && account.name.toLowerCase() === name.toLowerCase()) return true;
	return hostWithoutPath(account.endpoint) === hostWithoutPath(baseUrl);
}

function resourceNameFromBaseUrl(baseUrl: string | undefined): string | undefined {
	const host = hostWithoutPath(baseUrl);
	if (!host?.endsWith(".openai.azure.com")) return undefined;
	return host.split(".")[0];
}

function normalizeAzureBaseUrl(baseUrl: string | undefined): string | undefined {
	if (!baseUrl) return undefined;
	return baseUrl.replace(/\/+$/, "");
}

function hostWithoutPath(value: string | undefined): string | undefined {
	if (!value) return undefined;
	try {
		return new URL(value).host.toLowerCase();
	} catch {
		return undefined;
	}
}

function displayName(deploymentName: string, modelName: string): string {
	return deploymentName === modelName ? titleizeModel(modelName) : `${deploymentName} (${modelName})`;
}

function titleizeModel(value: string): string {
	return value.split("-").map(part => (part.toLowerCase() === "gpt" ? "GPT" : part)).join(" ");
}

function stringValue(value: unknown): string | undefined {
	return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function numberCapability(value: unknown): number | undefined {
	const number = typeof value === "number" ? value : typeof value === "string" ? Number(value) : Number.NaN;
	return Number.isFinite(number) && number > 0 ? number : undefined;
}

function isReasoningModel(modelName: string): boolean {
	return /(^gpt-5|codex)/i.test(modelName);
}

function isUnsupportedAgentModel(modelName: string, capabilities: Record<string, unknown>): boolean {
	return capabilities.imageGenerations === "true" || capabilities.audioTranscriptions === "true" || /image|transcribe|whisper/i.test(modelName);
}

function inputModalities(modelName: string, capabilities: Record<string, unknown>): ("text" | "image")[] {
	if (capabilities.image === "true" || capabilities.vision === "true" || /^gpt-[45]/i.test(modelName)) return ["text", "image"];
	return ["text"];
}
