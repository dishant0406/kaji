import * as fs from "node:fs/promises";
import { generateUnifiedDiffString } from "../edit/diff";
import { createLspWritethrough, type FileDiagnosticsResult } from "../lsp";
import type { ToolSession } from "./index";
import { ToolError } from "./tool-errors";
import {
	type EditSafetyTarget,
	internalUrlEditSafetyTarget,
	normalizeEditSafetyTargets,
	readEditSafetySnapshots,
} from "./edit-safety-targets";

export type EditTargetKind = "local-file" | "internal-url" | "client-bridge";

export interface EditSnapshot {
	path: string;
	absolutePath: string;
	targetKind: EditTargetKind;
	before: string | null;
	after: string | null;
	undoSupported: boolean;
	undoUnsupportedReason?: string;
}

export interface EditSafetyRecord {
	id: string;
	toolName: string;
	createdAt: string;
	snapshots: EditSnapshot[];
	undoneAt?: string;
}

export interface EditSafetyUndoResult {
	diagnostics: Array<{ path: string; diagnostics: FileDiagnosticsResult }>;
	diagnosticsRequestedPaths: string[];
}

export class EditSafetyLog {
	#records: EditSafetyRecord[] = [];
	#counter = 0;

	list(): EditSafetyRecord[] {
		return [...this.#records];
	}

	get(id: string): EditSafetyRecord | undefined {
		return this.#records.find(record => record.id === id);
	}

	lastUndoable(): EditSafetyRecord | undefined {
		return [...this.#records].reverse().find(record => isUndoableRecord(record));
	}

	async recordAround<T>(session: ToolSession, toolName: string, rawPaths: string[], run: () => Promise<T>): Promise<T> {
		const targets = await normalizeEditSafetyTargets(session, rawPaths);
		const before = await readEditSafetySnapshots(targets);
		const result = await run();
		const after = await readEditSafetySnapshots(targets);
		const snapshots = targets
			.map(target => buildSnapshot(target, before.get(target.absolutePath) ?? null, after.get(target.absolutePath) ?? null))
			.filter(snapshot => snapshot.before !== snapshot.after);
		this.#append(toolName, snapshots);
		return result;
	}

	recordExternalWrite(toolName: string, path: string, after: string, targetKind: EditTargetKind, reason: string): void {
		this.#append(toolName, [{ path, absolutePath: path, targetKind, before: null, after, undoSupported: false, undoUnsupportedReason: reason }]);
	}

	async undo(record: EditSafetyRecord, session: ToolSession): Promise<EditSafetyUndoResult> {
		if (!isUndoableRecord(record)) throw new ToolError(`Edit '${record.id}' cannot be undone safely.`);
		const diagnostics: EditSafetyUndoResult["diagnostics"] = [];
		const diagnosticsRequestedPaths: string[] = [];
		for (const snapshot of [...record.snapshots].reverse()) {
			const result = await restoreSnapshot(snapshot, session);
			if (result?.requested) diagnosticsRequestedPaths.push(snapshot.path);
			if (result?.diagnostics) diagnostics.push({ path: snapshot.path, diagnostics: result.diagnostics });
		}
		record.undoneAt = new Date().toISOString();
		return { diagnostics, diagnosticsRequestedPaths };
	}

	#append(toolName: string, snapshots: EditSnapshot[]): void {
		if (snapshots.length === 0) return;
		this.#counter += 1;
		this.#records.push({ id: `edit-${this.#counter}`, toolName, createdAt: new Date().toISOString(), snapshots });
	}
}

export function getEditSafetyLog(session: ToolSession): EditSafetyLog {
	session.editSafetyLog ??= new EditSafetyLog();
	return session.editSafetyLog;
}

export function formatEditSafetyDiff(record: EditSafetyRecord): string {
	const parts: string[] = [];
	for (const snapshot of record.snapshots) {
		parts.push(`--- ${snapshot.path}`);
		if (!snapshot.undoSupported && snapshot.undoUnsupportedReason) parts.push(`Undo unsupported: ${snapshot.undoUnsupportedReason}`);
		parts.push(generateUnifiedDiffString(snapshot.after ?? "", snapshot.before ?? "").diff || "(no textual diff)");
	}
	return parts.join("\n");
}

function isUndoableRecord(record: EditSafetyRecord): boolean {
	return !record.undoneAt && record.snapshots.length > 0 && record.snapshots.every(snapshot => snapshot.undoSupported);
}

function buildSnapshot(target: EditSafetyTarget, before: string | null, after: string | null): EditSnapshot {
	const undoUnsupportedReason = before === null && target.targetKind !== "local-file" ? `No previous ${target.targetKind} content was available.` : undefined;
	return {
		path: target.path,
		absolutePath: target.absolutePath,
		targetKind: target.targetKind,
		before,
		after,
		undoSupported: undoUnsupportedReason === undefined,
		undoUnsupportedReason,
	};
}

async function restoreSnapshot(snapshot: EditSnapshot, session: ToolSession) {
	if (snapshot.targetKind === "internal-url") return restoreInternalUrl(snapshot, session);
	return restoreLocalWithDiagnostics(snapshot, session);
}

async function restoreInternalUrl(snapshot: EditSnapshot, session: ToolSession): Promise<undefined> {
	const target = await internalUrlEditSafetyTarget(session, snapshot.path);
	await target?.restore(snapshot.before);
}

async function restoreLocalWithDiagnostics(snapshot: EditSnapshot, session: ToolSession) {
	if (snapshot.before === null) {
		await fs.rm(snapshot.absolutePath, { force: true });
		return undefined;
	}
	await fs.mkdir(pathDir(snapshot.absolutePath), { recursive: true });
	const enableDiagnostics = (session.enableLsp ?? true) && session.settings.get("lsp.diagnosticsOnWrite");
	if (!enableDiagnostics) {
		await Bun.write(snapshot.absolutePath, snapshot.before);
		return undefined;
	}
	const diagnostics = await createLspWritethrough(session.cwd, { enableDiagnostics })(snapshot.absolutePath, snapshot.before);
	return { requested: true, diagnostics };
}

function pathDir(filePath: string): string {
	const index = filePath.lastIndexOf("/");
	return index <= 0 ? "." : filePath.slice(0, index);
}
