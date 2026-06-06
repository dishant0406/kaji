import { beforeEach, describe, expect, test } from "bun:test";
import * as fs from "node:fs/promises";
import * as os from "node:os";
import * as path from "node:path";
import { Settings } from "../config/settings";
import { InternalUrlRouter, type InternalResource, type InternalUrl, type ProtocolHandler } from "../internal-urls";
import { getEditSafetyLog } from "./edit-safety";
import { createTools, type ToolSession } from "./index";
import { UndoTool } from "./undo";
import { WriteTool } from "./write";

async function withTempDir(run: (dir: string) => Promise<void>): Promise<void> {
	const dir = await fs.mkdtemp(path.join(os.tmpdir(), "kaji-edit-safety-"));
	try {
		await run(dir);
	} finally {
		await fs.rm(dir, { recursive: true, force: true });
	}
}

function session(cwd: string): ToolSession {
	return {
		cwd,
		hasUI: false,
		enableLsp: false,
		getSessionFile: () => null,
		getSessionSpawns: () => null,
		settings: Settings.isolated({ "checkpoint.enabled": true }),
	};
}

describe("edit safety", () => {
	beforeEach(async () => {
		await Settings.init({ inMemory: true, cwd: process.cwd() });
	});

	test("write records snapshots and undo restores previous content", async () => {
		await withTempDir(async dir => {
			const toolSession = session(dir);
			await Bun.write(path.join(dir, "a.txt"), "before\n");

			const write = new WriteTool(toolSession);
			await write.execute("write", { path: "a.txt", content: "after\n" });

			const record = getEditSafetyLog(toolSession).lastUndoable();
			expect(record?.toolName).toBe("write");
			expect(record?.snapshots[0]?.before).toBe("before\n");
			expect(record?.snapshots[0]?.after).toBe("after\n");
			expect(record?.snapshots[0]?.targetKind).toBe("local-file");
			expect(record?.snapshots[0]?.undoSupported).toBe(true);

			const undo = new UndoTool(toolSession);
			const preview = await undo.execute("undo", { preview: true });
			expect(preview.details?.undone).toBe(false);
			expect(await Bun.file(path.join(dir, "a.txt")).text()).toBe("after\n");

			const applied = await undo.execute("undo", {});
			expect(applied.details?.undone).toBe(true);
			expect(applied.details?.diagnostics).toEqual([]);
			expect(await Bun.file(path.join(dir, "a.txt")).text()).toBe("before\n");
		});
	});

	test("undo removes files created by this session", async () => {
		await withTempDir(async dir => {
			const toolSession = session(dir);
			const write = new WriteTool(toolSession);
			await write.execute("write", { path: "created.txt", content: "created\n" });

			await new UndoTool(toolSession).execute("undo", {});

			expect(await Bun.file(path.join(dir, "created.txt")).exists()).toBe(false);
		});
	});

	test("internal URL writes record restorable metadata", async () => {
		await withTempDir(async dir => {
			const toolSession = session(dir);
			const router = InternalUrlRouter.instance();
			router.register(new MemoryWriteHandler("editmem", "before"));

			await new WriteTool(toolSession).execute("write", { path: "editmem://note", content: "after" });
			const record = getEditSafetyLog(toolSession).lastUndoable();

			expect(record?.snapshots[0]).toMatchObject({
				path: "editmem://note",
				targetKind: "internal-url",
				before: "before",
				after: "after",
				undoSupported: true,
			});
			await new UndoTool(toolSession).execute("undo", {});
			expect(await router.resolve("editmem://note", { cwd: dir })).toMatchObject({ content: "before" });
		});
	});

	test("client bridge writes record non-undoable metadata", async () => {
		await withTempDir(async dir => {
			const written: Array<{ path: string; content: string }> = [];
			const toolSession = {
				...session(dir),
				getClientBridge: () => ({
					capabilities: { writeTextFile: true },
					writeTextFile: async entry => {
						written.push(entry);
					},
				}),
			} satisfies ToolSession;

			await new WriteTool(toolSession).execute("write", { path: "bridge.txt", content: "remote" });

			expect(written[0]?.content).toBe("remote");
			expect(getEditSafetyLog(toolSession).list()[0]?.snapshots[0]).toMatchObject({
				path: "bridge.txt",
				targetKind: "client-bridge",
				after: "remote",
				undoSupported: false,
			});
			await expect(new UndoTool(toolSession).execute("undo", {})).rejects.toThrow(/No undoable edits/);
		});
	});

	test("createTools exposes undo", async () => {
		const tools = await createTools(session(process.cwd()), ["undo"]);
		expect(tools.map(tool => tool.name)).toContain("undo");
	});
});


class MemoryWriteHandler implements ProtocolHandler {
	readonly immutable = false;
	#content: string;

	constructor(readonly scheme: string, content: string) {
		this.#content = content;
	}

	async resolve(url: InternalUrl): Promise<InternalResource> {
		return { url: url.toString(), content: this.#content, contentType: "text/plain" };
	}

	async write(_url: InternalUrl, content: string): Promise<void> {
		this.#content = content;
	}
}
