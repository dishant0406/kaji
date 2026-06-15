import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { validateCustomProviderConnection } from "@oh-my-pi/pi-coding-agent/config/custom-provider-validation";
import type { AzureCliRunner } from "@oh-my-pi/pi-coding-agent/config/azure-cli-runner";

class FakeAzureRunner implements AzureCliRunner {
	constructor(private readonly currentKey = "current-key") {}

	async run(args: string[]): Promise<unknown> {
		if (args.includes("deployment") && args.includes("list")) return [deployment("gpt-5.5")];
		if (args.includes("keys") && args.includes("list")) return { key1: this.currentKey, key2: "secondary-key" };
		throw new Error(`Unexpected az args: ${args.join(" ")}`);
	}
}

describe("custom provider validation", () => {
	let tempDir: string;
	let modelsPath: string;
	let previousAzureKey: string | undefined;

	beforeEach(() => {
		tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "kaji-custom-provider-validation-"));
		modelsPath = path.join(tempDir, "models.yml");
		previousAzureKey = Bun.env.AZURE_OPENAI_API_KEY;
	});

	afterEach(() => {
		if (previousAzureKey === undefined) delete Bun.env.AZURE_OPENAI_API_KEY;
		else Bun.env.AZURE_OPENAI_API_KEY = previousAzureKey;
		fs.rmSync(tempDir, { recursive: true, force: true });
	});

	test("detects a stale literal Azure OpenAI key", async () => {
		writeAzureProvider(modelsPath, "stale-key");
		const result = await validateCustomProviderConnection(baseInput(), {
			modelsPath,
			runner: new FakeAzureRunner("current-key"),
			fetch: async () => Response.json({ error: { message: "invalid key" } }, { status: 401 }),
		});

		expect(result.ok).toBe(false);
		expect(result.statusCode).toBe(401);
		expect(result.keyStatus.source).toBe("literal");
		expect(result.keyMatchesAzureResource).toBe(false);
		expect(result.message).toContain("does not match");
	});

	test("validates with an environment variable key without exposing it", async () => {
		Bun.env.AZURE_OPENAI_API_KEY = "current-key";
		writeAzureProvider(modelsPath, "AZURE_OPENAI_API_KEY");
		let sentKey: string | null = null;

		const result = await validateCustomProviderConnection(baseInput(), {
			modelsPath,
			runner: new FakeAzureRunner("current-key"),
			fetch: async (_url, init) => {
				sentKey = new Headers(init?.headers).get("api-key");
				return Response.json({ id: "resp", output: [] });
			},
		});

		expect(result.ok).toBe(true);
		expect(result.keyStatus.source).toBe("environment");
		expect(result.keyStatus.name).toBe("AZURE_OPENAI_API_KEY");
		expect(sentKey).toBe("current-key");
		expect(JSON.stringify(result)).not.toContain("current-key");
	});

	test("reports missing environment variable before sending a request", async () => {
		delete Bun.env.AZURE_OPENAI_API_KEY;
		writeAzureProvider(modelsPath, "AZURE_OPENAI_API_KEY");
		let requested = false;

		const result = await validateCustomProviderConnection(baseInput(), {
			modelsPath,
			runner: new FakeAzureRunner(),
			fetch: async () => {
				requested = true;
				return Response.json({});
			},
		});

		expect(result.ok).toBe(false);
		expect(result.title).toContain("unavailable");
		expect(result.keyStatus.resolved).toBe(false);
		expect(requested).toBe(false);
	});
});

function writeAzureProvider(modelsPath: string, apiKey: string) {
	fs.writeFileSync(
		modelsPath,
		[
			"providers:",
			"  zerocarbon-codex:",
			"    baseUrl: https://zerocarbon-codex.openai.azure.com/openai/v1",
			`    apiKey: ${apiKey}`,
			"    api: azure-openai-responses",
			"    auth: apiKey",
			"    discovery:",
			"      type: azure-openai-deployments",
			"      resourceGroup: DefaultResourceGroup-eastus2",
			"      accountName: zerocarbon-codex",
			"    models:",
			"      - id: gpt-5.5",
		].join("\n"),
	);
}

function baseInput() {
	return {
		id: "zerocarbon-codex",
		baseUrl: "https://zerocarbon-codex.openai.azure.com/openai/v1",
		api: "azure-openai-responses" as const,
		auth: "apiKey" as const,
		discovery: { type: "azure-openai-deployments" as const, resourceGroup: "DefaultResourceGroup-eastus2", accountName: "zerocarbon-codex" },
		models: [{ id: "gpt-5.5" }],
	};
}

function deployment(name: string) {
	return {
		name,
		properties: {
			capabilities: { responses: "true", chatCompletion: "true" },
			model: { name, version: "2026-01-01" },
			provisioningState: "Succeeded",
		},
	};
}
