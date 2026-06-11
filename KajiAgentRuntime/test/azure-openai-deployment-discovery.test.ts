import { describe, expect, test } from "bun:test";
import { discoverAzureOpenAIDeployments } from "@oh-my-pi/pi-coding-agent/config/azure-openai-deployment-discovery";
import type { AzureCliRunner } from "@oh-my-pi/pi-coding-agent/config/azure-cli-runner";

class FakeAzureRunner implements AzureCliRunner {
	constructor(private readonly deployments: unknown[]) {}

	async run(args: string[]): Promise<unknown> {
		if (args.includes("account") && args.includes("list") && !args.includes("deployment")) {
			return [
				{
					name: "zerocarbon-codex",
					resourceGroup: "DefaultResourceGroup-eastus2",
					properties: { endpoint: "https://zerocarbon-codex.openai.azure.com/" },
				},
			];
		}
		if (args.includes("deployment") && args.includes("list")) return this.deployments;
		throw new Error(`Unexpected az args: ${args.join(" ")}`);
	}
}

describe("Azure OpenAI deployment discovery", () => {
	test("discovers response-capable deployments and filters image/audio deployments", async () => {
		const result = await discoverAzureOpenAIDeployments(
			{
				provider: "zerocarbon-codex",
				api: "azure-openai-responses",
				baseUrl: "https://zerocarbon-codex.openai.azure.com/openai/v1",
				discovery: { type: "azure-openai-deployments" },
			},
			new FakeAzureRunner([
				deployment("gpt-5.5", "gpt-5.5", { responses: "true", chatCompletion: "true" }),
				deployment("prod-codex", "gpt-5.3-codex", { responses: "true", chatCompletion: "false" }),
				deployment("gpt-image-2", "gpt-image-2", { imageGenerations: "true" }),
				deployment("gpt-4o-mini-transcribe", "gpt-4o-mini-transcribe", { audioTranscriptions: "true" }),
				deployment("failed", "gpt-5.5", { responses: "true" }, "Failed"),
			]),
		);

		expect(result.account.name).toBe("zerocarbon-codex");
		expect(result.account.resourceGroup).toBe("DefaultResourceGroup-eastus2");
		expect(result.models.map(model => model.id)).toEqual(["gpt-5.5", "prod-codex"]);
		expect(result.models[0].api).toBe("azure-openai-responses");
		expect(result.models[0].reasoning).toBe(true);
		expect(result.models[0].input).toEqual(["text", "image"]);
		expect(result.models[1].name).toBe("prod-codex (gpt-5.3-codex)");
	});

	test("uses explicit account metadata without listing accounts", async () => {
		const calls: string[][] = [];
		const runner: AzureCliRunner = {
			async run(args) {
				calls.push(args);
				return [deployment("gpt-5.4", "gpt-5.4", { responses: "true" })];
			},
		};

		const result = await discoverAzureOpenAIDeployments(
			{
				provider: "custom",
				api: "azure-openai-responses",
				baseUrl: "https://example.openai.azure.com/openai/v1",
				discovery: {
					type: "azure-openai-deployments",
					accountName: "custom",
					resourceGroup: "rg",
					subscription: "sub",
				},
			},
			runner,
		);

		expect(result.models.map(model => model.id)).toEqual(["gpt-5.4"]);
		expect(calls).toHaveLength(1);
		expect(calls[0]).toContain("--subscription");
		expect(calls[0]).toContain("sub");
	});
});

function deployment(name: string, modelName: string, capabilities: Record<string, string>, state = "Succeeded") {
	return {
		name,
		properties: {
			capabilities,
			model: { name: modelName, version: "2026-01-01" },
			provisioningState: state,
		},
	};
}
