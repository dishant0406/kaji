import { describe, expect, test } from "bun:test";
import { resolveModelHarnessProfile } from "./model-harness-profile";

describe("model harness profile", () => {
	test("selects family-specific edit and reasoning defaults", () => {
		expect(resolveModelHarnessProfile("gpt-5-codex").preferredEditTool).toBe("edit");
		expect(resolveModelHarnessProfile("gemini-2.5-pro").preferredEditTool).toBe("patch");
		expect(resolveModelHarnessProfile("local/qwen").forceToolChoiceSupported).toBe(false);
	});
});
