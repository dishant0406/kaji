export function agentMode() {
	return process.env.KAJI_PARENT_AGENT_MODE ?? "parent";
}
