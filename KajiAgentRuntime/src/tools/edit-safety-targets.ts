import * as fs from "node:fs/promises";
import { InternalUrlRouter, parseInternalUrl } from "../internal-urls";
import type { ToolSession } from "./index";
import { isInternalUrlPath } from "./path-utils";
import { resolvePlanPath } from "./plan-mode-guard";
import { ToolError } from "./tool-errors";
import type { EditTargetKind } from "./edit-safety";

export interface EditSafetyTarget {
	path: string;
	absolutePath: string;
	targetKind: EditTargetKind;
	read(): Promise<string | null>;
	restore(content: string | null): Promise<void>;
}

export async function normalizeEditSafetyTargets(session: ToolSession, rawPaths: string[]): Promise<EditSafetyTarget[]> {
	const seen = new Set<string>();
	const out: EditSafetyTarget[] = [];
	for (const rawPath of rawPaths) {
		const target = await normalizeTarget(session, rawPath);
		if (!target || seen.has(target.absolutePath)) continue;
		seen.add(target.absolutePath);
		out.push(target);
	}
	return out;
}

export async function internalUrlEditSafetyTarget(
	session: ToolSession,
	rawPath: string,
): Promise<EditSafetyTarget | undefined> {
	const router = InternalUrlRouter.instance();
	if (!router.canHandle(rawPath)) return undefined;
	const parsed = parseInternalUrl(rawPath);
	const scheme = parsed.protocol.replace(/:$/, "").toLowerCase();
	const handler = router.getHandler(scheme);
	if (!handler?.write || handler.immutable) return undefined;
	return {
		path: rawPath,
		absolutePath: rawPath,
		targetKind: "internal-url",
		read: async () => (await router.resolve(rawPath, { cwd: session.cwd, settings: session.settings })).content,
		restore: async content => {
			if (content === null) throw new ToolError(`Cannot delete internal URL '${rawPath}' during undo.`);
			await handler.write?.(parsed, content, { cwd: session.cwd });
		},
	};
}

export async function readEditSafetySnapshots(targets: EditSafetyTarget[]): Promise<Map<string, string | null>> {
	const out = new Map<string, string | null>();
	for (const target of targets) out.set(target.absolutePath, await target.read());
	return out;
}

async function normalizeTarget(session: ToolSession, rawPath: string): Promise<EditSafetyTarget | undefined> {
	if (!rawPath) return undefined;
	if (isInternalUrlPath(rawPath)) return internalUrlEditSafetyTarget(session, rawPath);
	try {
		const absolutePath = resolvePlanPath(session, rawPath);
		return {
			path: rawPath,
			absolutePath,
			targetKind: "local-file",
			read: () => readFileOrNull(absolutePath),
			restore: content => restoreLocal(absolutePath, content),
		};
	} catch {
		return undefined;
	}
}

async function readFileOrNull(filePath: string): Promise<string | null> {
	try {
		return await Bun.file(filePath).text();
	} catch {
		return null;
	}
}

async function restoreLocal(filePath: string, content: string | null): Promise<void> {
	if (content === null) {
		await fs.rm(filePath, { force: true });
		return;
	}
	await fs.mkdir(pathDir(filePath), { recursive: true });
	await Bun.write(filePath, content);
}

function pathDir(filePath: string): string {
	const index = filePath.lastIndexOf("/");
	return index <= 0 ? "." : filePath.slice(0, index);
}
