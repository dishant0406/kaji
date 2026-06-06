import type { AgentTool, AgentToolResult } from "@oh-my-pi/pi-agent-core";
import * as z from "zod/v4";
import { getRuntimeProfile, runtimeProfiles } from "../runtime/profile";
import { resolveModelHarnessProfile } from "../runtime/model-harness-profile";
import type { ToolSession } from "../sdk";

const runtimeProfileDumpSchema = z
	.object({
		profile_id: z.string().optional().describe("Optional runtime profile id to inspect"),
	})
	.describe("dump runtime profile and model harness settings");

export interface RuntimeProfileDumpDetails {
	profile: ReturnType<typeof getRuntimeProfile>;
	availableProfiles: string[];
	modelHarnessProfile: ReturnType<typeof resolveModelHarnessProfile>;
	activeModel?: string;
}

export class RuntimeProfileDumpTool implements AgentTool<typeof runtimeProfileDumpSchema, RuntimeProfileDumpDetails> {
	readonly name = "runtime_profile_dump";
	readonly approval = "read" as const;
	readonly label = "Runtime Profile Dump";
	readonly summary = "Inspect Kaji runtime profile configuration";
	readonly description = "Dump the active or requested Kaji runtime profile and model harness profile.";
	readonly parameters = runtimeProfileDumpSchema;
	readonly strict = true;
	readonly loadMode = "discoverable";

	constructor(private readonly session: ToolSession) {}

	async execute(_toolCallId: string, params: z.infer<typeof runtimeProfileDumpSchema>): Promise<AgentToolResult<RuntimeProfileDumpDetails>> {
		const id = params.profile_id || "kaji-rpc-build";
		const profile = getRuntimeProfile(id as never);
		const activeModel = this.session.getActiveModelString?.();
		const modelHarnessProfile = resolveModelHarnessProfile(activeModel);
		const availableProfiles = runtimeProfiles().map(candidate => candidate.id);
		return {
			content: [{ type: "text", text: formatRuntimeProfileDump(profile, modelHarnessProfile, availableProfiles, activeModel) }],
			details: { profile, availableProfiles, modelHarnessProfile, activeModel },
		};
	}
}

function formatRuntimeProfileDump(
	profile: RuntimeProfileDumpDetails["profile"],
	modelHarnessProfile: RuntimeProfileDumpDetails["modelHarnessProfile"],
	availableProfiles: string[],
	activeModel?: string,
): string {
	return [
		`Runtime profile: ${profile.id}`,
		`Mode: ${profile.mode}`,
		`Tools: ${profile.toolPatterns.join(", ")}`,
		`Hidden tools: ${profile.hiddenToolPatterns.join(", ")}`,
		`Permission mode: ${profile.permissionMode}`,
		`Active model: ${activeModel ?? "unknown"}`,
		`Preferred edit tool: ${modelHarnessProfile.preferredEditTool}`,
		`Available profiles: ${availableProfiles.join(", ")}`,
	].join("\n");
}
