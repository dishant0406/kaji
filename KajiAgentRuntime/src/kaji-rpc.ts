#!/usr/bin/env bun

process.env.KAJI_AGENT_RUNTIME = "1";
process.env.PI_CONFIG_DIR = process.env.PI_CONFIG_DIR || ".kaji/agent-runtime";
process.env.PI_NOTIFICATIONS = "off";
process.env.PI_NO_TITLE = "1";

import type { AssistantMessageEventStream, Context, Model, SimpleStreamOptions } from "@oh-my-pi/pi-ai";
import { createMockModel } from "@oh-my-pi/pi-ai/providers/mock";
import { setAgentDir, setProjectDir } from "@oh-my-pi/pi-utils";
import { parseArgs } from "./cli/args";
import { ModelRegistry, type ProviderConfigInput } from "./config/model-registry";
import { applyRpcDefaultSettingOverrides } from "./main";
import { runRpcMode } from "./modes/rpc/rpc-mode";
import { createAgentSession, discoverAuthStorage } from "./sdk";
import { SessionManager } from "./session/session-manager";
import { Settings } from "./config/settings";

function defaultAgentDir(): string {
	const home = process.env.HOME || process.cwd();
	return `${home}/Library/Application Support/Kaji/AgentRuntime`;
}

function configureEnvironment(): string {
	const agentDir = process.env.KAJI_AGENT_DIR || defaultAgentDir();
	setAgentDir(agentDir);
	return agentDir;
}

function registerKajiMockModel(modelRegistry: ModelRegistry): void {
	if (process.env.KAJI_AGENT_ENABLE_MOCK !== "1") return;
	const mock = createMockModel({
		id: "kaji-mock",
		provider: "kaji-mock",
		handler: context => ({ content: [mockResponse(context)] }),
	});
	modelRegistry.authStorage.setRuntimeApiKey("kaji-mock", "kaji-mock");
	modelRegistry.registerProvider(
		"kaji-mock",
		{
			baseUrl: "mock://",
			apiKey: "kaji-mock",
			api: "mock",
			streamSimple: (_model: Model, context: Context, options?: SimpleStreamOptions): AssistantMessageEventStream =>
				mock.stream(mock, context, options),
			models: [
				{
					id: "kaji-mock",
					name: "Kaji Mock",
					api: "mock",
					reasoning: false,
					input: ["text", "image"],
					cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
					contextWindow: 128000,
					maxTokens: 16384,
				},
			],
		} satisfies ProviderConfigInput,
		"kaji/mock",
	);
}

function mockResponse(context: Context): string {
	const latest = [...context.messages].reverse().find(message => message.role === "user");
	const text = latest && typeof latest.content === "string" ? latest.content : "";
	return text.trim().length > 0
		? `Kaji mock received: ${text.trim()}`
		: "Kaji mock runtime is ready.";
}

async function main(): Promise<void> {
	const agentDir = configureEnvironment();
	const args = parseArgs(["--mode", "rpc", "--approval-mode", "read-allow", ...process.argv.slice(2)]);
	const cwd = args.cwd || process.cwd();
	setProjectDir(cwd);
	const settings = await Settings.init({ cwd, agentDir });
	applyRpcDefaultSettingOverrides(settings);
	if (args.approvalMode) settings.override("tools.approvalMode", args.approvalMode);
	const authStorage = await discoverAuthStorage(agentDir);
	const modelRegistry = new ModelRegistry(authStorage);
	registerKajiMockModel(modelRegistry);
	const sessionDir = args.sessionDir || `${agentDir}/sessions`;
	const sessionManager = args.noSession ? SessionManager.inMemory() : SessionManager.create(cwd, sessionDir);
	const { session, setToolUIContext } = await createAgentSession({
		cwd,
		agentDir,
		sessionManager,
		authStorage,
		modelRegistry,
		settings,
		hasUI: true,
		autoApprove: args.autoApprove ?? false,
		toolNames: args.tools,
		enableLsp: args.noLsp ? false : undefined,
		enableMCP: process.env.KAJI_AGENT_ENABLE_MCP === "1",
		thinkingLevel: args.thinking,
	});
	await runRpcMode(session, setToolUIContext);
}

main().catch(error => {
	const message = error instanceof Error ? error.message : String(error);
	process.stdout.write(`${JSON.stringify({ type: "fatal_error", error: message })}\n`);
	process.exit(1);
});
