import { describe, expect, it, vi } from "bun:test";
import * as ai from "@oh-my-pi/pi-ai";
import { Effort, getBundledModel } from "@oh-my-pi/pi-ai";
import { generateRpcCommitMessage } from "../src/modes/rpc/commit-message";

function model(id: string) {
	const found = getBundledModel("anthropic", id);
	if (!found) throw new Error(`Missing bundled model ${id}`);
	return found;
}

function sessionFor(models = [model("claude-sonnet-4-5")]) {
	return {
		sessionId: "session-1",
		settings: {
			getModelRole: (role: string) => (role === "commit" ? `${models[0].provider}/${models[0].id}:low` : undefined),
			getStorage: () => undefined,
			get: () => ({}),
		},
		getAvailableModels: () => models,
		modelRegistry: {
			getApiKey: async () => "test-key",
			getCanonicalVariants: () => [],
		},
	} as never;
}

describe("RPC commit message generation", () => {
	it("uses the selected provider and model", async () => {
		const selected = model("claude-sonnet-4-5");
		const completeSimple = vi.spyOn(ai, "completeSimple").mockResolvedValue({
			stopReason: "end_turn",
			content: [{ type: "text", text: "`Improve commit settings`" }],
		} as never);

		const result = await generateRpcCommitMessage(sessionFor([selected]), {
			provider: selected.provider,
			modelId: selected.id,
			promptMessage: "inventory",
			thinkingLevel: Effort.Minimal,
		});

		expect(result.message).toBe("Improve commit settings");
		expect(result.model.id).toBe(selected.id);
		expect(completeSimple.mock.calls[0]?.[0]).toBe(selected);
		expect(completeSimple.mock.calls[0]?.[2]).toMatchObject({ apiKey: "test-key", reasoning: Effort.Minimal });
		vi.restoreAllMocks();
	});

	it("falls back to the commit role when no explicit model is selected", async () => {
		const selected = model("claude-sonnet-4-5");
		const completeSimple = vi.spyOn(ai, "completeSimple").mockResolvedValue({
			stopReason: "end_turn",
			content: [{ type: "text", text: "Refine commit generator" }],
		} as never);

		const result = await generateRpcCommitMessage(sessionFor([selected]), { promptMessage: "inventory" });

		expect(result.model.id).toBe(selected.id);
		expect(result.message).toBe("Refine commit generator");
		expect(completeSimple.mock.calls[0]?.[2]).toMatchObject({ reasoning: Effort.Low });
		vi.restoreAllMocks();
	});
});
