import type { Component } from "@oh-my-pi/pi-tui";
import { logger } from "@oh-my-pi/pi-utils";
import type { CustomTool, CustomToolContext, CustomToolSessionEvent } from "./types";
import type { ExtensionContext, ExtensionFactory, ToolDefinition } from "../extensions";

function createCustomToolContext(ctx: ExtensionContext): CustomToolContext {
	return {
		sessionManager: ctx.sessionManager,
		modelRegistry: ctx.modelRegistry,
		model: ctx.model,
		isIdle: ctx.isIdle,
		hasQueuedMessages: ctx.hasPendingMessages,
		abort: ctx.abort,
	};
}

export function isCustomTool(tool: CustomTool | ToolDefinition): tool is CustomTool {
	// To distinguish, we mark converted tools with a hidden symbol property.
	// If the tool doesn't have this marker, it's a CustomTool that needs conversion.
	return !(tool as any).__isToolDefinition;
}

const TOOL_DEFINITION_MARKER = Symbol("__isToolDefinition");

export function customToolToDefinition(tool: CustomTool): ToolDefinition {
	const definition: ToolDefinition & { [TOOL_DEFINITION_MARKER]: true } = {
		name: tool.name,
		label: tool.label,
		description: tool.description,
		parameters: tool.parameters,
		hidden: tool.hidden,
		deferrable: tool.deferrable,
		mcpServerName: tool.mcpServerName,
		mcpToolName: tool.mcpToolName,
		execute: (toolCallId, params, signal, onUpdate, ctx) =>
			tool.execute(toolCallId, params, onUpdate, createCustomToolContext(ctx), signal),
		onSession: tool.onSession ? (event, ctx) => tool.onSession?.(event, createCustomToolContext(ctx)) : undefined,
		renderCall: tool.renderCall,
		renderResult: tool.renderResult
			? (result, options, theme): Component => {
					const component = tool.renderResult?.(
						result,
						{ expanded: options.expanded, isPartial: options.isPartial, spinnerFrame: options.spinnerFrame },
						theme,
					);
					// Return empty component if undefined to match Component type requirement
					return component ?? ({ render: () => [] } as unknown as Component);
				}
			: undefined,
		[TOOL_DEFINITION_MARKER]: true,
	};
	return definition;
}

export function createCustomToolsExtension(tools: CustomTool[]): ExtensionFactory {
	return api => {
		for (const tool of tools) {
			api.registerTool(customToolToDefinition(tool));
		}

		const runOnSession = async (event: CustomToolSessionEvent, ctx: ExtensionContext) => {
			for (const tool of tools) {
				if (!tool.onSession) continue;
				try {
					await tool.onSession(event, createCustomToolContext(ctx));
				} catch (err) {
					logger.warn("Custom tool onSession error", { tool: tool.name, error: String(err) });
				}
			}
		};

		api.on("session_start", async (_event, ctx) =>
			runOnSession({ reason: "start", previousSessionFile: undefined }, ctx),
		);
		api.on("session_switch", async (event, ctx) =>
			runOnSession({ reason: "switch", previousSessionFile: event.previousSessionFile }, ctx),
		);
		api.on("session_branch", async (event, ctx) =>
			runOnSession({ reason: "branch", previousSessionFile: event.previousSessionFile }, ctx),
		);
		api.on("session_tree", async (_event, ctx) =>
			runOnSession({ reason: "tree", previousSessionFile: undefined }, ctx),
		);
		api.on("session_shutdown", async (_event, ctx) =>
			runOnSession({ reason: "shutdown", previousSessionFile: undefined }, ctx),
		);
		api.on("auto_compaction_start", async (event, ctx) =>
			runOnSession({ reason: "auto_compaction_start", trigger: event.reason, action: event.action }, ctx),
		);
		api.on("auto_compaction_end", async (event, ctx) =>
			runOnSession(
				{
					reason: "auto_compaction_end",
					action: event.action,
					result: event.result,
					aborted: event.aborted,
					willRetry: event.willRetry,
					errorMessage: event.errorMessage,
				},
				ctx,
			),
		);
		api.on("auto_retry_start", async (event, ctx) =>
			runOnSession(
				{
					reason: "auto_retry_start",
					attempt: event.attempt,
					maxAttempts: event.maxAttempts,
					delayMs: event.delayMs,
					errorMessage: event.errorMessage,
				},
				ctx,
			),
		);
		api.on("auto_retry_end", async (event, ctx) =>
			runOnSession(
				{
					reason: "auto_retry_end",
					success: event.success,
					attempt: event.attempt,
					finalError: event.finalError,
				},
				ctx,
			),
		);
		api.on("ttsr_triggered", async (event, ctx) =>
			runOnSession({ reason: "ttsr_triggered", rules: event.rules }, ctx),
		);
		api.on("todo_reminder", async (event, ctx) =>
			runOnSession(
				{
					reason: "todo_reminder",
					todos: event.todos,
					attempt: event.attempt,
					maxAttempts: event.maxAttempts,
				},
				ctx,
			),
		);
	};
}

