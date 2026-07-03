import type { AgentTool, AgentToolResult } from "@oh-my-pi/pi-agent-core";
import * as z from "zod/v4";
import { emptyPermissionServiceSnapshot, type PermissionServiceSnapshot } from "../permissions";
import type { RuntimeTelemetrySnapshot } from "../runtime/telemetry";
import type { SessionStats } from "../session/agent-session";
import type { ToolSession } from "../sdk";

const runtimeTelemetryDumpSchema = z.object({}).describe("dump runtime telemetry counters");

export interface RuntimeTelemetryDumpDetails {
	telemetry: RuntimeTelemetrySnapshot;
	permission: PermissionServiceSnapshot;
	sessionStats?: SessionStats;
}

export class RuntimeTelemetryDumpTool implements AgentTool<typeof runtimeTelemetryDumpSchema, RuntimeTelemetryDumpDetails> {
	readonly name = "runtime_telemetry_dump";
	readonly approval = "read" as const;
	readonly label = "Runtime Telemetry Dump";
	readonly summary = "Inspect Kaji runtime telemetry counters";
	readonly description = "Dump tool, retry, compaction, prompt, discovery, permission, and session usage counters.";
	readonly parameters = runtimeTelemetryDumpSchema;
	readonly strict = true;
	readonly loadMode = "discoverable";

	constructor(private readonly session: ToolSession) {}

	async execute(): Promise<AgentToolResult<RuntimeTelemetryDumpDetails>> {
		const telemetry = this.session.getRuntimeTelemetrySnapshot?.() ?? emptyTelemetry();
		const permission = this.session.getPermissionSnapshot?.() ?? emptyPermissionServiceSnapshot();
		const sessionStats = this.session.getSessionStats?.();
		const details = { telemetry, permission, sessionStats };
		return { content: [{ type: "text", text: formatRuntimeTelemetryDump(details) }], details };
	}
}

function formatRuntimeTelemetryDump(details: RuntimeTelemetryDumpDetails): string {
	return [
		`Events: ${details.telemetry.totalEvents}`,
		`Tool executions: ${details.telemetry.toolEnds} (${details.telemetry.toolFailures} failures)`,
		`Retries: ${details.telemetry.autoRetryStarts} started, ${details.telemetry.autoRetryEnds} ended`,
		`Compactions: ${details.telemetry.autoCompactionStarts} started, ${details.telemetry.autoCompactionEnds} ended`,
		`Prompt rebuilds: ${details.telemetry.promptRebuilds} (${details.telemetry.lastPromptCharacterCount} chars)`,
		`Discovered activations: ${details.telemetry.activatedDiscoveredTools} (${details.telemetry.activatedMcpTools} MCP)`,
		`Permission asks: ${details.permission.requestCount ?? 0}, denies: ${details.permission.denyCount ?? 0}`,
		`Host permissions: ${details.permission.requestCountByCategory.host ?? 0} asks, ${details.permission.denyCountByCategory.host ?? 0} denies`,
		`Browser permissions: ${details.permission.requestCountByCategory.browser ?? 0} asks, ${details.permission.denyCountByCategory.browser ?? 0} denies`,
		`Session tokens: ${details.sessionStats?.tokens.total ?? 0}`,
	].join("\n");
}

function emptyTelemetry(): RuntimeTelemetrySnapshot {
	return {
		totalEvents: 0,
		toolStarts: 0,
		toolEnds: 0,
		toolFailures: 0,
		toolFailuresByName: {},
		toolCallsByName: {},
		autoRetryStarts: 0,
		autoRetryEnds: 0,
		autoCompactionStarts: 0,
		autoCompactionEnds: 0,
		promptRebuilds: 0,
		lastPromptCharacterCount: 0,
		lastPromptBlockCount: 0,
		activatedMcpTools: 0,
		activatedDiscoveredTools: 0,
		lastActivatedTools: [],
	};
}
