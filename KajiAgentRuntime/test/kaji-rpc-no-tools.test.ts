import { describe, expect, test } from "bun:test";

describe("Kaji RPC no-tools isolation", () => {
	test("disables tools and project discovery when requested", async () => {
		const source = await Bun.file(new URL("../src/kaji-rpc.ts", import.meta.url)).text();
		expect(source).toContain('toolNames: noTools ? ["__none__"] : args.tools');
		expect(source).toContain("disableExtensionDiscovery: noTools");
		expect(source).toContain("skills: noTools ? [] : undefined");
		expect(source).toContain("rules: noTools ? [] : undefined");
		expect(source).toContain("contextFiles: noTools ? [] : undefined");
		expect(source).toContain("enableMCP: noTools ? false");
		expect(source).toContain("skipPythonPreflight: noTools");
	});
});
