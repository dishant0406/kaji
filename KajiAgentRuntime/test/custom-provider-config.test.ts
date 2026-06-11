import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
	deleteCustomProvider,
	listCustomProviders,
	saveCustomProvider,
} from "@oh-my-pi/pi-coding-agent/config/custom-provider-config";

describe("custom provider config", () => {
	let tempDir: string;
	let modelsPath: string;

	beforeEach(() => {
		tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "kaji-custom-provider-"));
		modelsPath = path.join(tempDir, "models.yml");
	});

	afterEach(() => {
		fs.rmSync(tempDir, { recursive: true, force: true });
	});

	test("saves a manual provider and preserves top-level equivalence", async () => {
		fs.writeFileSync(
			modelsPath,
			[
				"equivalence:",
				"  overrides:",
				"    old/provider: claude-sonnet-4-6",
				"providers:",
				"  anthropic:",
				"    baseUrl: https://gateway.internal/anthropic",
			].join("\n"),
		);

		const result = await saveCustomProvider(
			{
				id: "myco",
				baseUrl: "https://llm.internal/v1",
				apiKey: "MYCO_API_KEY",
				api: "openai-responses",
				auth: "apiKey",
				models: [
					{
						id: "myco-large",
						name: "MyCo Large",
						reasoning: true,
						input: ["text", "image"],
						contextWindow: 200000,
						maxTokens: 32000,
					},
				],
			},
			modelsPath,
		);

		expect(result.providers.map(provider => provider.id)).toEqual(["anthropic", "myco"]);
		const content = fs.readFileSync(modelsPath, "utf-8");
		expect(content).toContain("equivalence:");
		expect(content).toContain("myco-large");
		expect(content).toContain("MYCO_API_KEY");
	});

	test("saves a discoverable keyless local provider", async () => {
		const result = await saveCustomProvider(
			{
				id: "llama.cpp",
				baseUrl: "http://127.0.0.1:8080",
				api: "openai-responses",
				auth: "none",
				discovery: { type: "llama.cpp" },
			},
			modelsPath,
		);

		expect(result.providers[0].id).toBe("llama.cpp");
		expect(result.providers[0].auth).toBe("none");
		expect(result.providers[0].discovery?.type).toBe("llama.cpp");
		expect(fs.readFileSync(modelsPath, "utf-8")).not.toContain("apiKey");
	});

	test("saves an Azure OpenAI deployments provider without manual models", async () => {
		const result = await saveCustomProvider(
			{
				id: "zerocarbon-codex",
				baseUrl: "https://zerocarbon-codex.openai.azure.com/openai/v1",
				apiKey: "AZURE_OPENAI_API_KEY",
				api: "azure-openai-responses",
				auth: "apiKey",
				discovery: { type: "azure-openai-deployments", resourceGroup: "DefaultResourceGroup-eastus2" },
			},
			modelsPath,
		);

		expect(result.providers[0].id).toBe("zerocarbon-codex");
		expect(result.providers[0].discovery?.type).toBe("azure-openai-deployments");
		expect(result.providers[0].models).toEqual([]);
	});

	test("preserves existing advanced model fields when editing known model", async () => {
		fs.writeFileSync(
			modelsPath,
			[
				"providers:",
				"  myco:",
				"    baseUrl: https://old.example/v1",
				"    apiKey: MYCO_API_KEY",
				"    api: openai-responses",
				"    models:",
				"      - id: myco-large",
				"        cost: { input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75 }",
			].join("\n"),
		);

		await saveCustomProvider(
			{
				id: "myco",
				baseUrl: "https://new.example/v1",
				apiKey: "MYCO_API_KEY",
				api: "openai-responses",
				auth: "apiKey",
				models: [{ id: "myco-large", name: "MyCo Large", input: ["text"] }],
			},
			modelsPath,
		);

		const content = fs.readFileSync(modelsPath, "utf-8");
		expect(content).toContain("https://new.example/v1");
		expect(content).toContain("cost:");
		expect(content).toContain("cacheWrite");
	});

	test("rejects invalid manual provider before writing", async () => {
		await expect(
			saveCustomProvider(
				{
					id: "bad provider",
					api: "openai-responses",
					auth: "apiKey",
					models: [{ id: "model" }],
				},
				modelsPath,
			),
		).rejects.toThrow("Provider ID");
		expect(fs.existsSync(modelsPath)).toBe(false);
	});

	test("deletes one provider without removing others", async () => {
		await saveCustomProvider(
			{ id: "a", baseUrl: "http://a", apiKey: "A_KEY", api: "openai-responses", models: [{ id: "one" }] },
			modelsPath,
		);
		await saveCustomProvider(
			{ id: "b", baseUrl: "http://b", apiKey: "B_KEY", api: "openai-responses", models: [{ id: "two" }] },
			modelsPath,
		);

		const result = await deleteCustomProvider("a", modelsPath);

		expect(result.providers.map(provider => provider.id)).toEqual(["b"]);
		expect(fs.readFileSync(modelsPath, "utf-8")).toContain("B_KEY");
		expect((await listCustomProviders(modelsPath)).providers).toHaveLength(1);
	});
});
