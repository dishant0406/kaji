import { describe, expect, it } from "bun:test";
import * as path from "node:path";

describe("issue #1150 — binary build worker entrypoints", () => {
	const packageRoot = path.resolve(import.meta.dir, "..");
	const devScriptPath = path.join(packageRoot, "scripts/build-binary.ts");

	it("scripts/build-binary.ts lists every local worker as an explicit --compile entrypoint", async () => {
		const source = await Bun.file(devScriptPath).text();
		const devEntrypoints = ["./src/eval/js/worker-entry.ts"];
		for (const entry of devEntrypoints) {
			expect(
				source.includes(`"${entry}"`),
				`scripts/build-binary.ts must include "${entry}" as a --compile entrypoint so dev binaries emit workers into bunfs`,
			).toBe(true);
		}
	});
});
