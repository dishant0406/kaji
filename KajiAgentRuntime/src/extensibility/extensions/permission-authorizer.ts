import type { AgentTool, AgentToolContext } from "@oh-my-pi/pi-agent-core";
import { PermissionService } from "../../permissions/permission-service";
import type { ApprovalMode } from "../../tools/approval";
import type { ExtensionUIContext } from "./types";

export interface ExtensionPermissionContext {
	permissionService: PermissionService;
	hasUI: boolean;
	uiContext: ExtensionUIContext;
}

export async function authorizeExtensionToolCall(
	context: ExtensionPermissionContext,
	tool: Pick<AgentTool, "name" | "approval" | "formatApprovalDetails">,
	params: unknown,
	toolContext?: AgentToolContext,
): Promise<void> {
	const settings = toolContext?.settings;
	const configuredMode = (settings?.get("tools.approvalMode") ?? "yolo") as ApprovalMode;
	const approvalMode: ApprovalMode = toolContext?.autoApprove === true ? "yolo" : configuredMode;
	const userPolicies = (settings?.get("tools.approval") ?? {}) as Record<string, unknown>;
	await context.permissionService.authorizeRuntimeToolCall({
		tool,
		args: params,
		approvalMode,
		userPolicies,
		hasUI: context.hasUI,
		requestApproval: async message => {
			const choice = await context.uiContext.select(message, ["Approve", "Deny"]);
			return choice === "Approve";
		},
	});
}
