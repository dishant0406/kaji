import type { AgentTool, AgentToolResult } from "@oh-my-pi/pi-agent-core";
import * as z from "zod/v4";
import { emptyPermissionServiceSnapshot, type PermissionServiceSnapshot } from "../permissions";
import type { ToolSession } from "../sdk";

const permissionRulesDumpSchema = z.object({}).describe("dump active permission rules and ACP gate state");

export interface PermissionRulesDumpDetails {
	rules: PermissionServiceSnapshot["rules"];
	sessionDecisionCount: number;
	persistentDecisionCount: number;
	gatedAcpTools: string[];
	requestCount: number;
	denyCount: number;
	requestCountByKey: Record<string, number>;
	denyCountByKey: Record<string, number>;
	requestCountByCategory: PermissionServiceSnapshot["requestCountByCategory"];
	denyCountByCategory: PermissionServiceSnapshot["denyCountByCategory"];
}

export class PermissionRulesDumpTool implements AgentTool<typeof permissionRulesDumpSchema, PermissionRulesDumpDetails> {
	readonly name = "permission_rules_dump";
	readonly approval = "read" as const;
	readonly label = "Permission Rules Dump";
	readonly summary = "Inspect Kaji permission rules";
	readonly description = "Dump active permission rules, durable decisions, and ACP-gated tools.";
	readonly parameters = permissionRulesDumpSchema;
	readonly strict = true;
	readonly loadMode = "discoverable";

	constructor(private readonly session: ToolSession) {}

	async execute(): Promise<AgentToolResult<PermissionRulesDumpDetails>> {
		const snapshot = this.session.getPermissionSnapshot?.() ?? emptyPermissionServiceSnapshot();
		const details = {
			rules: snapshot.rules,
			sessionDecisionCount: snapshot.sessionDecisionCount,
			persistentDecisionCount: snapshot.persistentDecisionCount,
			gatedAcpTools: snapshot.gatedAcpTools,
			requestCount: snapshot.requestCount,
			denyCount: snapshot.denyCount,
			requestCountByKey: snapshot.requestCountByKey,
			denyCountByKey: snapshot.denyCountByKey,
			requestCountByCategory: snapshot.requestCountByCategory,
			denyCountByCategory: snapshot.denyCountByCategory,
		};
		return { content: [{ type: "text", text: formatPermissionRulesDump(details) }], details };
	}
}

function formatPermissionRulesDump(details: PermissionRulesDumpDetails): string {
	const rules = details.rules.map(rule => `${rule.pattern}:${rule.decision}`).join(", ") || "none";
	return [
		`Permission rules (${details.rules.length}): ${rules}`,
		`Session decisions: ${details.sessionDecisionCount}`,
		`Persistent decisions: ${details.persistentDecisionCount}`,
		`Permission asks: ${details.requestCount}`,
		`Permission denies: ${details.denyCount}`,
		`Permission asks by key: ${formatRecord(details.requestCountByKey)}`,
		`Permission denies by key: ${formatRecord(details.denyCountByKey)}`,
		`Permission asks by category: ${formatRecord(details.requestCountByCategory)}`,
		`Permission denies by category: ${formatRecord(details.denyCountByCategory)}`,
		`ACP gated tools: ${details.gatedAcpTools.join(", ") || "none"}`,
	].join("\n");
}

function formatRecord(record: Record<string, number>): string {
	const entries = Object.entries(record).sort(([left], [right]) => left.localeCompare(right));
	return entries.map(([key, value]) => `${key}:${value}`).join(", ") || "none";
}
