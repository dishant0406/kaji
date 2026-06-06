import type { AgentTool, AgentToolResult } from "@oh-my-pi/pi-agent-core";
import * as z from "zod/v4";
import type { FileDiagnosticsResult } from "../lsp";
import { formatEditSafetyDiff, getEditSafetyLog } from "./edit-safety";
import type { ToolSession } from "./index";
import { ToolError } from "./tool-errors";

const undoSchema = z
	.object({
		edit_id: z.string().optional().describe("Specific edit id to undo; defaults to the last undoable edit"),
		preview: z.boolean().optional().describe("Show the undo diff without applying it"),
	})
	.describe("undo a recorded edit from this session");

export interface UndoToolDetails {
	editId: string;
	paths: string[];
	preview: boolean;
	undone: boolean;
	diff: string;
	diagnostics: Array<{ path: string; diagnostics: FileDiagnosticsResult }>;
	diagnosticsRequestedPaths: string[];
}

export class UndoTool implements AgentTool<typeof undoSchema, UndoToolDetails> {
	readonly name = "undo";
	readonly approval = "write" as const;
	readonly label = "Undo";
	readonly summary = "Undo a recorded edit from this session";
	readonly description = "Undo the last recorded edit or preview the undo diff before applying it.";
	readonly parameters = undoSchema;
	readonly strict = true;
	readonly concurrency = "exclusive";
	readonly loadMode = "discoverable";

	constructor(private readonly session: ToolSession) {}

	async execute(_toolCallId: string, params: z.infer<typeof undoSchema>): Promise<AgentToolResult<UndoToolDetails>> {
		const log = getEditSafetyLog(this.session);
		const record = params.edit_id ? log.get(params.edit_id) : log.lastUndoable();
		if (!record) throw new ToolError(params.edit_id ? `Edit '${params.edit_id}' was not found.` : "No undoable edits recorded.");
		if (record.undoneAt) throw new ToolError(`Edit '${record.id}' was already undone.`);
		const diff = formatEditSafetyDiff(record);
		const preview = params.preview === true;
		const undoResult = preview ? { diagnostics: [], diagnosticsRequestedPaths: [] } : await log.undo(record, this.session);
		const paths = record.snapshots.map(snapshot => snapshot.path);
		return {
			content: [{ type: "text", text: formatUndoResult(record.id, paths, diff, preview, undoResult.diagnosticsRequestedPaths) }],
			details: { editId: record.id, paths, preview, undone: !preview, diff, ...undoResult },
		};
	}
}

function formatUndoResult(editId: string, paths: string[], diff: string, preview: boolean, diagnosticsPaths: string[]): string {
	const action = preview ? "Undo preview" : "Undo applied";
	const lines = [`${action}: ${editId}`, `Paths: ${paths.join(", ")}`];
	if (diagnosticsPaths.length > 0) lines.push(`Diagnostics requested: ${diagnosticsPaths.join(", ")}`);
	lines.push(diff);
	return lines.join("\n");
}
