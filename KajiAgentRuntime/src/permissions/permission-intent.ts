import { expandApplyPatchToEntries } from "../edit";
import { resolveToCwd } from "../tools/path-utils";

export interface PermissionIntent {
	title: string;
	paths?: string[];
	cacheKey: string;
}

export function getPermissionIntent(toolName: string, args: unknown): PermissionIntent | undefined {
	const a = args && typeof args === "object" && !Array.isArray(args) ? (args as Record<string, unknown>) : {};
	if (toolName === "bash") return { title: getStringProperty(a, "command")?.slice(0, 80) || toolName, cacheKey: toolName };
	if (toolName === "delete") return fileIntent(toolName, a, "path", "Delete");
	if (toolName === "move") return moveIntent(a);
	if (toolName !== "edit") return undefined;
	const intent = getEditDestructiveIntent(args);
	if (!intent) return undefined;
	if (intent.kind === "delete") return { title: `Delete ${intent.paths[0] ?? "edit target"}`, paths: intent.paths, cacheKey: "edit:delete" };
	const [from, to] = intent.paths;
	return { title: from && to ? `Move ${from} to ${to}` : `Move ${from ?? to ?? "edit target"}`, paths: intent.paths, cacheKey: "edit:move" };
}

export function extractPermissionLocations(args: unknown, cwd: string, explicitPaths?: string[]): { path: string; line?: number }[] {
	const out: { path: string; line?: number }[] = [];
	for (const value of explicitPaths ?? collectArgPaths(args)) {
		try {
			const resolved = resolveToCwd(value, cwd);
			if (!out.some(location => location.path === resolved)) out.push({ path: resolved });
		} catch {}
	}
	return out;
}

export function commandContent(toolName: string, args: unknown) {
	if (toolName !== "bash" || !args || typeof args !== "object" || Array.isArray(args)) return {};
	const command = getStringProperty(args as Record<string, unknown>, "command");
	return command ? { content: [{ type: "content" as const, content: { type: "text" as const, text: `$ ${command}` } }] } : {};
}

function getStringProperty(value: Record<string, unknown>, key: string): string | undefined {
	const candidate = value[key];
	return typeof candidate === "string" ? candidate : undefined;
}

function fileIntent(toolName: string, args: Record<string, unknown>, key: string, verb: string) {
	const p = getStringProperty(args, key);
	return { title: p ? `${verb} ${p}` : toolName, paths: p ? [p] : undefined, cacheKey: toolName };
}

function moveIntent(args: Record<string, unknown>) {
	const from = getStringProperty(args, "oldPath") ?? getStringProperty(args, "path") ?? getStringProperty(args, "from");
	const to = getStringProperty(args, "newPath") ?? getStringProperty(args, "to") ?? getStringProperty(args, "destination");
	return { title: from && to ? `Move ${from} to ${to}` : from ? `Move ${from}` : "move", paths: [from, to].filter(Boolean) as string[], cacheKey: "move" };
}

function getEditDestructiveIntent(args: unknown): { kind: "delete" | "move"; paths: string[] } | undefined {
	if (!args || typeof args !== "object" || Array.isArray(args)) return undefined;
	const a = args as Record<string, unknown>;
	const editIntent = getStructuredEditDestructiveIntent(a);
	if (editIntent) return editIntent;
	const input = getStringProperty(a, "input");
	if (!input) return undefined;
	try {
		const entries = expandApplyPatchToEntries({ input });
		const deleteEntry = entries.find(entry => entry.op === "delete");
		if (deleteEntry) return { kind: "delete", paths: [deleteEntry.path] };
		const moveEntry = entries.find(entry => entry.rename);
		if (moveEntry?.rename) return { kind: "move", paths: [moveEntry.path, moveEntry.rename] };
	} catch {}
	return undefined;
}

function getStructuredEditDestructiveIntent(args: Record<string, unknown>): { kind: "delete" | "move"; paths: string[] } | undefined {
	const edits = Array.isArray(args.edits) ? args.edits : undefined;
	if (!edits) return undefined;
	const path = getStringProperty(args, "path");
	if (path) {
		for (const edit of edits) {
			if (!edit || typeof edit !== "object" || Array.isArray(edit)) continue;
			if (getStringProperty(edit as Record<string, unknown>, "op") === "delete") return { kind: "delete", paths: [path] };
		}
	}
	for (const edit of edits) {
		if (!edit || typeof edit !== "object" || Array.isArray(edit)) continue;
		const entry = edit as Record<string, unknown>;
		const rename = getStringProperty(entry, "rename");
		if (getStringProperty(entry, "op") !== "create" && rename) return { kind: "move", paths: path ? [path, rename] : [rename] };
	}
	return undefined;
}

function collectArgPaths(args: unknown): string[] {
	if (!args || typeof args !== "object" || Array.isArray(args)) return [];
	const a = args as Record<string, unknown>;
	const arrayPaths = Array.isArray(a.paths) ? a.paths : [];
	return [a.path, a.file, ...arrayPaths, a.oldPath, a.newPath, a.from, a.to, a.source, a.destination].filter(
		(item): item is string => typeof item === "string" && item.length > 0,
	);
}
