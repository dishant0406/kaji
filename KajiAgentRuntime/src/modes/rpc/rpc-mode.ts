/**
 * RPC mode: Headless operation with JSON stdin/stdout protocol.
 *
 * Used for embedding the agent in other applications.
 * Receives commands as JSON on stdin, outputs events and responses as JSON on stdout.
 *
 * Protocol:
 * - Commands: JSON objects with `type` field, optional `id` for correlation
 * - Responses: JSON objects with `type: "response"`, `command`, `success`, and optional `data`/`error`
 * - Events: AgentSessionEvent objects streamed as they occur
 * - Extension UI: Extension UI requests are emitted, client responds with extension_ui_response
 */
import { getOAuthProviders } from "@oh-my-pi/pi-ai/utils/oauth";
import { $env, readJsonl, Snowflake } from "@oh-my-pi/pi-utils";
import { deleteCustomProvider, listCustomProviders, previewCustomProviderModels, saveCustomProvider } from "../../config/custom-provider-config";
import { validateCustomProviderConnection } from "../../config/custom-provider-validation";
import { BUILTIN_SLASH_COMMAND_DEFS } from "../../slash-commands/builtin-registry";
import { getKnownRoleIds, getRoleInfo } from "../../config/model-registry";
import { formatModelSelectorValue } from "../../config/model-resolver";
import { generateRpcCommitMessage } from "./commit-message";
import { buildSkillPromptMessage } from "../../extensibility/skills";
import { expandSlashCommand } from "../../extensibility/slash-commands";
import { HistoryStorage } from "../../session/history-storage";
import { SessionManager, type SessionInfo } from "../../session/session-manager";
import { readSubagentTranscript } from "../../session/subagent-transcript-reader";
import {
	TASK_SUBAGENT_LIFECYCLE_CHANNEL,
	TASK_SUBAGENT_PROGRESS_CHANNEL,
	type SubagentLifecyclePayload,
	type SubagentProgressPayload,
} from "../../task/types";
import type {
	ExtensionUIContext,
	ExtensionUIDialogOptions,
	ExtensionWidgetOptions,
} from "../../extensibility/extensions";
import { type Theme, theme } from "../../modes/theme/theme";
import type { AgentSession } from "../../session/agent-session";
import { initializeExtensions } from "../runtime-init";
import { isRpcHostToolResult, isRpcHostToolUpdate, RpcHostToolBridge } from "./host-tools";
import { isRpcHostUriResult, RpcHostUriBridge } from "./host-uris";
import type {
	RpcCommand,
	RpcExtensionUIRequest,
	RpcExtensionUIResponse,
	RpcHostToolCallRequest,
	RpcHostToolCancelRequest,
	RpcHostToolDefinition,
	RpcHostUriCancelRequest,
	RpcHostUriRequest,
	RpcResponse,
	RpcSessionState,
} from "./rpc-types";

// Re-export types for consumers
export type * from "./rpc-types";

export type PendingExtensionRequest = {
	resolve: (response: RpcExtensionUIResponse) => void;
	reject: (error: Error) => void;
};

type RpcOutput = (
	obj:
		| RpcResponse
		| RpcExtensionUIRequest
		| RpcHostToolCallRequest
		| RpcHostToolCancelRequest
		| RpcHostUriRequest
		| RpcHostUriCancelRequest
		| object,
) => void;

function normalizeHostToolDefinitions(tools: RpcHostToolDefinition[]): RpcHostToolDefinition[] {
	return tools.map((tool, index) => {
		const name = typeof tool.name === "string" ? tool.name.trim() : "";
		if (!name) {
			throw new Error(`Host tool at index ${index} must provide a non-empty name`);
		}
		const description = typeof tool.description === "string" ? tool.description.trim() : "";
		if (!description) {
			throw new Error(`Host tool "${name}" must provide a non-empty description`);
		}
		if (!tool.parameters || typeof tool.parameters !== "object" || Array.isArray(tool.parameters)) {
			throw new Error(`Host tool "${name}" must provide a JSON Schema object`);
		}
		const label = typeof tool.label === "string" && tool.label.trim() ? tool.label.trim() : name;
		const approval = ["read", "write", "exec"].includes(String(tool.approval)) ? tool.approval : undefined;
		return {
			name,
			label,
			description,
			parameters: tool.parameters,
			hidden: tool.hidden === true,
			...(approval ? { approval } : {}),
		};
	});
}

function parseValueDialogResponse(
	response: RpcExtensionUIResponse,
	dialogOptions: ExtensionUIDialogOptions | undefined,
): string | undefined {
	if ("cancelled" in response && response.cancelled) {
		if (response.timedOut) dialogOptions?.onTimeout?.();
		return undefined;
	}
	if ("value" in response) return response.value;
	return undefined;
}

function shouldEmitRpcTitles(): boolean {
	const raw = $env.PI_RPC_EMIT_TITLE;
	if (!raw) return false;
	const normalized = raw.trim().toLowerCase();
	return normalized === "1" || normalized === "true" || normalized === "yes" || normalized === "on";
}

export function requestRpcEditor(
	pendingRequests: Map<string, PendingExtensionRequest>,
	output: RpcOutput,
	title: string,
	prefill?: string,
	dialogOptions?: ExtensionUIDialogOptions,
	editorOptions?: { promptStyle?: boolean },
): Promise<string | undefined> {
	if (dialogOptions?.signal?.aborted) return Promise.resolve(undefined);

	const id = Snowflake.next() as string;
	const { promise, resolve, reject } = Promise.withResolvers<string | undefined>();
	let settled = false;

	const cleanup = () => {
		dialogOptions?.signal?.removeEventListener("abort", onAbort);
		pendingRequests.delete(id);
	};
	const finish = (value: string | undefined) => {
		if (settled) return;
		settled = true;
		cleanup();
		resolve(value);
	};
	const fail = (error: Error) => {
		if (settled) return;
		settled = true;
		cleanup();
		reject(error);
	};
	const onAbort = () => {
		output({
			type: "extension_ui_request",
			id: Snowflake.next() as string,
			method: "cancel",
			targetId: id,
		} as RpcExtensionUIRequest);
		finish(undefined);
	};

	dialogOptions?.signal?.addEventListener("abort", onAbort, { once: true });
	pendingRequests.set(id, {
		resolve: response => {
			if ("cancelled" in response && response.cancelled) {
				finish(undefined);
			} else if ("value" in response) {
				finish(response.value);
			} else {
				finish(undefined);
			}
		},
		reject: fail,
	});
	output({
		type: "extension_ui_request",
		id,
		method: "editor",
		title,
		prefill,
		promptStyle: editorOptions?.promptStyle,
	} as RpcExtensionUIRequest);
	return promise;
}
/**
 * Run in RPC mode.
 * Listens for JSON commands on stdin, outputs events and responses on stdout.
 */
export async function runRpcMode(
	session: AgentSession,
	setToolUIContext?: (uiContext: ExtensionUIContext, hasUI: boolean) => void,
): Promise<never> {
	// Signal to RPC clients that the server is ready to accept commands
	// Suppress terminal notifications: they write \x07 (BEL) or OSC sequences directly to
	// process.stdout with no newline, which the reader merges with the next JSON line and
	// breaks JSON.parse. In RPC mode stdout is the JSON protocol channel — nothing else
	// may write there.
	process.env.PI_NOTIFICATIONS = "off";

	process.stdout.write(`${JSON.stringify({ type: "ready" })}\n`);
	const output = (obj: RpcResponse | RpcExtensionUIRequest | object) => {
		process.stdout.write(`${JSON.stringify(obj)}\n`);
	};
	const emitRpcTitles = shouldEmitRpcTitles();

	const success = <T extends RpcCommand["type"]>(
		id: string | undefined,
		command: T,
		data?: object | null,
	): RpcResponse => {
		if (data === undefined) {
			return { id, type: "response", command, success: true } as RpcResponse;
		}
		return { id, type: "response", command, success: true, data } as RpcResponse;
	};

	const error = (id: string | undefined, command: string, message: string): RpcResponse => {
		return { id, type: "response", command, success: false, error: message };
	};

	const pendingExtensionRequests = new Map<string, PendingExtensionRequest>();
	const hostToolBridge = new RpcHostToolBridge(output);
	const hostUriBridge = new RpcHostUriBridge(output);

	// Shutdown request flag (wrapped in object to allow mutation with const)
	const shutdownState = { requested: false };

	/**
	 * Extension UI context that uses the RPC protocol.
	 */
	class RpcExtensionUIContext implements ExtensionUIContext {
		constructor(
			private pendingRequests: Map<string, PendingExtensionRequest>,
			private output: (obj: RpcResponse | RpcExtensionUIRequest | object) => void,
		) {}

		/** Helper for dialog methods with signal/timeout support */
		#createDialogPromise<T>(
			opts: ExtensionUIDialogOptions | undefined,
			defaultValue: T,
			request: Record<string, unknown>,
			parseResponse: (response: RpcExtensionUIResponse) => T,
		): Promise<T> {
			if (opts?.signal?.aborted) return Promise.resolve(defaultValue);

			const id = Snowflake.next() as string;
			const { promise, resolve, reject } = Promise.withResolvers<T>();
			let timeoutId: NodeJS.Timeout | undefined;

			const cleanup = () => {
				if (timeoutId) clearTimeout(timeoutId);
				opts?.signal?.removeEventListener("abort", onAbort);
				this.pendingRequests.delete(id);
			};

			const onAbort = () => {
				cleanup();
				resolve(defaultValue);
			};
			opts?.signal?.addEventListener("abort", onAbort, { once: true });

			if (opts?.timeout !== undefined) {
				timeoutId = setTimeout(() => {
					opts.onTimeout?.();
					cleanup();
					resolve(defaultValue);
				}, opts.timeout);
			}

			this.pendingRequests.set(id, {
				resolve: (response: RpcExtensionUIResponse) => {
					cleanup();
					resolve(parseResponse(response));
				},
				reject,
			});
			this.output({ type: "extension_ui_request", id, ...request } as RpcExtensionUIRequest);
			return promise;
		}

		select(title: string, options: string[], dialogOptions?: ExtensionUIDialogOptions): Promise<string | undefined> {
			return this.#createDialogPromise(
				dialogOptions,
				undefined,
				{ method: "select", title, options, timeout: dialogOptions?.timeout },
				response => parseValueDialogResponse(response, dialogOptions),
			);
		}

		confirm(title: string, message: string, dialogOptions?: ExtensionUIDialogOptions): Promise<boolean> {
			return this.#createDialogPromise(
				dialogOptions,
				false,
				{ method: "confirm", title, message, timeout: dialogOptions?.timeout },
				response => {
					if ("cancelled" in response && response.cancelled) {
						if (response.timedOut) dialogOptions?.onTimeout?.();
						return false;
					}
					if ("confirmed" in response) return response.confirmed;
					return false;
				},
			);
		}

		input(
			title: string,
			placeholder?: string,
			dialogOptions?: ExtensionUIDialogOptions,
		): Promise<string | undefined> {
			return this.#createDialogPromise(
				dialogOptions,
				undefined,
				{ method: "input", title, placeholder, timeout: dialogOptions?.timeout },
				response => parseValueDialogResponse(response, dialogOptions),
			);
		}

		loginInput(prompt: { message: string; placeholder?: string; allowEmpty?: boolean }): Promise<string | undefined> {
			return this.#createDialogPromise(
				undefined,
				undefined,
				{
					method: "input",
					title: prompt.message,
					placeholder: prompt.placeholder,
					allowEmpty: prompt.allowEmpty,
					isSecure: isSecretPrompt(prompt.message, prompt.placeholder),
				},
				response => parseValueDialogResponse(response),
			);
		}

		onTerminalInput(): () => void {
			// Raw terminal input not supported in RPC mode
			return () => {};
		}

		notify(message: string, type?: "info" | "warning" | "error"): void {
			// Fire and forget - no response needed
			this.output({
				type: "extension_ui_request",
				id: Snowflake.next() as string,
				method: "notify",
				message,
				notifyType: type,
			} as RpcExtensionUIRequest);
		}

		setStatus(key: string, text: string | undefined): void {
			// Fire and forget - no response needed
			this.output({
				type: "extension_ui_request",
				id: Snowflake.next() as string,
				method: "setStatus",
				statusKey: key,
				statusText: text,
			} as RpcExtensionUIRequest);
		}

		setWorkingMessage(_message?: string): void {
			// Not supported in RPC mode
		}

		setWidget(key: string, content: unknown, options?: ExtensionWidgetOptions): void {
			// Only support string arrays in RPC mode - factory functions are ignored
			if (content === undefined || Array.isArray(content)) {
				this.output({
					type: "extension_ui_request",
					id: Snowflake.next() as string,
					method: "setWidget",
					widgetKey: key,
					widgetLines: content as string[] | undefined,
					widgetPlacement: options?.placement,
				} as RpcExtensionUIRequest);
			}
			// Component factories are not supported in RPC mode - would need TUI access
		}

		setFooter(_factory: unknown): void {
			// Custom footer not supported in RPC mode - requires TUI access
		}

		setHeader(_factory: unknown): void {
			// Custom header not supported in RPC mode - requires TUI access
		}

		setTitle(title: string): void {
			// Title updates are low-value noise for most RPC hosts; opt in via PI_RPC_EMIT_TITLE=1.
			if (!emitRpcTitles) return;
			this.output({
				type: "extension_ui_request",
				id: Snowflake.next() as string,
				method: "setTitle",
				title,
			} as RpcExtensionUIRequest);
		}

		async custom(): Promise<never> {
			// Custom UI not supported in RPC mode
			return undefined as never;
		}

		pasteToEditor(text: string): void {
			// Paste handling not supported in RPC mode - falls back to setEditorText
			this.setEditorText(text);
		}

		setEditorText(text: string): void {
			// Fire and forget - host can implement editor control
			this.output({
				type: "extension_ui_request",
				id: Snowflake.next() as string,
				method: "set_editor_text",
				text,
			} as RpcExtensionUIRequest);
		}

		getEditorText(): string {
			// Synchronous method can't wait for RPC response
			// Host should track editor state locally if needed
			return "";
		}

		async editor(
			title: string,
			prefill?: string,
			dialogOptions?: ExtensionUIDialogOptions,
			editorOptions?: { promptStyle?: boolean },
		): Promise<string | undefined> {
			return requestRpcEditor(this.pendingRequests, this.output, title, prefill, dialogOptions, editorOptions);
		}

		get theme(): Theme {
			return theme;
		}

		getAllThemes(): Promise<{ name: string; path: string | undefined }[]> {
			return Promise.resolve([]);
		}

		getTheme(_name: string): Promise<Theme | undefined> {
			return Promise.resolve(undefined);
		}

		setTheme(_theme: string | Theme): Promise<{ success: boolean; error?: string }> {
			// Theme switching not supported in RPC mode
			return Promise.resolve({ success: false, error: "Theme switching not supported in RPC mode" });
		}

		getToolsExpanded() {
			// Tool expansion not supported in RPC mode - no TUI
			return false;
		}

		setToolsExpanded(_expanded: boolean) {
			// Tool expansion not supported in RPC mode - no TUI
		}

		setEditorComponent(): void {
			// Custom editor components not supported in RPC mode
		}
	}

	// Wire up UI context for tool execution (ask tool, etc.) and extensions.
	// A single shared instance routes all responses received on stdin to the
	// correct waiting promise regardless of which code path created the request.
	const rpcUiContext = new RpcExtensionUIContext(pendingExtensionRequests, output);
	setToolUIContext?.(rpcUiContext, true);

	// Set up extensions with RPC-based UI context
	await initializeExtensions(session, {
		reportSendError: (action, err) => {
			output(error(undefined, action, err.message));
		},
		reportRuntimeError: err => {
			output({ type: "extension_error", extensionPath: err.extensionPath, event: err.event, error: err.error });
		},
		onShutdown: () => {
			shutdownState.requested = true;
		},
		uiContext: rpcUiContext,
	});

	// Output all agent events as JSON
	session.subscribe(event => {
		output(event);
	});

	const subagents = new Map<string, SubagentLifecyclePayload & { progress?: SubagentProgressPayload["progress"] }>();
	session.eventBus?.on(TASK_SUBAGENT_LIFECYCLE_CHANNEL, payload => {
		const lifecycle = payload as SubagentLifecyclePayload;
		const existing = subagents.get(lifecycle.id);
		subagents.set(lifecycle.id, { ...existing, ...lifecycle });
		output({ type: "subagent_lifecycle", data: lifecycle });
	});
	session.eventBus?.on(TASK_SUBAGENT_PROGRESS_CHANNEL, payload => {
		const progress = payload as SubagentProgressPayload;
		const existing = subagents.get(progress.progress.id);
		subagents.set(progress.progress.id, {
			...(existing ?? {
				id: progress.progress.id,
				agent: progress.agent,
				agentSource: progress.agentSource,
				description: progress.progress.description,
				status: progress.progress.status === "running" ? "started" : progress.progress.status,
				index: progress.index,
				sessionFile: progress.sessionFile,
			}),
			progress: progress.progress,
			sessionFile: progress.sessionFile ?? existing?.sessionFile,
		});
		output({ type: "subagent_progress", data: progress });
	});

	// Handle a single command
	const handleCommand = async (command: RpcCommand): Promise<RpcResponse> => {
		const id = command.id;

		switch (command.type) {
			// =================================================================
			// Prompting
			// =================================================================

			case "prompt": {
				// Don't await - events will stream
				// Extension commands are executed immediately, file prompt templates are expanded
				// If streaming and streamingBehavior specified, queues via steer/followUp
				session
					.prompt(command.message, {
						images: command.images,
						streamingBehavior: command.streamingBehavior,
					})
					.catch(e => output(error(id, "prompt", e.message)));
				return success(id, "prompt");
			}

			case "steer": {
				await session.steer(command.message, command.images);
				return success(id, "steer");
			}

			case "follow_up": {
				await session.followUp(command.message, command.images);
				return success(id, "follow_up");
			}

			case "abort": {
				await session.abort();
				return success(id, "abort");
			}

			case "abort_and_prompt": {
				await session.abort();
				session
					.prompt(command.message, { images: command.images })
					.catch(e => output(error(id, "abort_and_prompt", e.message)));
				return success(id, "abort_and_prompt");
			}

			case "new_session": {
				const options = command.parentSession ? { parentSession: command.parentSession } : undefined;
				const cancelled = !(await session.newSession(options));
				return success(id, "new_session", { cancelled });
			}

			// =================================================================
			// State
			// =================================================================

			case "get_state": {
				const state: RpcSessionState = {
					model: session.model,
					thinkingLevel: session.thinkingLevel,
					isStreaming: session.isStreaming,
					isCompacting: session.isCompacting,
					steeringMode: session.steeringMode,
					followUpMode: session.followUpMode,
					interruptMode: session.interruptMode,
					sessionFile: session.sessionFile,
					sessionId: session.sessionId,
					sessionName: session.sessionName,
					autoCompactionEnabled: session.autoCompactionEnabled,
					messageCount: session.messages.length,
					queuedMessageCount: session.queuedMessageCount,
					todoPhases: session.getTodoPhases(),
					systemPrompt: session.systemPrompt,
					dumpTools: session.agent.state.tools.map(tool => ({
						name: tool.name,
						description: tool.description,
						parameters: tool.parameters,
					})),
					contextUsage: session.getContextUsage(),
				};
				return success(id, "get_state", state);
			}

			case "set_todos": {
				session.setTodoPhases(command.phases);
				return success(id, "set_todos", { todoPhases: session.getTodoPhases() });
			}

			case "set_host_tools": {
				const tools = normalizeHostToolDefinitions(command.tools);
				const rpcTools = hostToolBridge.setTools(tools);
				await session.refreshRpcHostTools(rpcTools);
				return success(id, "set_host_tools", { toolNames: tools.map(tool => tool.name) });
			}

			case "set_host_uri_schemes": {
				try {
					const schemes = hostUriBridge.setSchemes(command.schemes);
					return success(id, "set_host_uri_schemes", { schemes });
				} catch (err) {
					return error(id, "set_host_uri_schemes", err instanceof Error ? err.message : String(err));
				}
			}

			// =================================================================
			// Model
			// =================================================================

			case "set_model": {
				const models = session.getAvailableModels();
				const model = models.find(m => m.provider === command.provider && m.id === command.modelId);
				if (!model) {
					return error(id, "set_model", `Model not found: ${command.provider}/${command.modelId}`);
				}
				await session.setModel(model);
				return success(id, "set_model", model);
			}

			case "get_model_config": {
				const models = session.getAvailableModels();
				return success(id, "get_model_config", {
					models,
					roles: getKnownRoleIds(session.settings).map(role => {
						const info = getRoleInfo(role, session.settings);
						return {
							role,
							name: info.name,
							tag: info.tag,
							color: info.color,
							selector: session.settings.getModelRole(role),
						};
					}),
					cycleOrder: session.settings.get("cycleOrder"),
					currentModel: session.model,
					thinkingLevel: session.thinkingLevel,
				});
			}

			case "set_model_role": {
				const role = command.role ?? readString(command.data, "role") ?? "default";
				const provider = command.provider ?? readString(command.data, "provider") ?? "";
				const modelId = command.modelId ?? readString(command.data, "modelId") ?? "";
				const thinkingLevel = command.thinkingLevel ?? readString(command.data, "thinkingLevel");
				const temporary = command.temporary ?? readBoolean(command.data, "temporary") ?? false;
				const model = session.getAvailableModels().find(m => m.provider === provider && m.id === modelId);
				if (!model) return error(id, "set_model_role", `Model not found: ${provider}/${modelId}`);
				if (temporary) {
					await session.setModelTemporary(model, thinkingLevel as any);
				} else if (role === "default") {
					await session.setModel(model, "default", { selector: `${provider}/${modelId}`, thinkingLevel: thinkingLevel as any });
				} else {
					session.settings.setModelRole(role, formatModelSelectorValue(`${provider}/${modelId}`, thinkingLevel as any));
				}
				return success(id, "set_model_role", { role, model, thinkingLevel, temporary });
			}

			case "cycle_model": {
				const result = await session.cycleModel();
				if (!result) {
					return success(id, "cycle_model", null);
				}
				return success(id, "cycle_model", result);
			}

			case "get_available_models": {
				const models = session.getAvailableModels();
				return success(id, "get_available_models", { models });
			}

			case "generate_commit_message": {
				try {
					return success(id, "generate_commit_message", await generateRpcCommitMessage(session, command));
				} catch (err) {
					return error(id, "generate_commit_message", err instanceof Error ? err.message : String(err));
				}
			}

			case "get_custom_providers": {
				try {
					return success(id, "get_custom_providers", await listCustomProviders());
				} catch (err) {
					return error(id, "get_custom_providers", err instanceof Error ? err.message : String(err));
				}
			}

			case "save_custom_provider": {
				try {
					const providers = await saveCustomProvider(command.data);
					await session.modelRegistry.refresh();
					return success(id, "save_custom_provider", { ...providers, models: session.getAvailableModels() });
				} catch (err) {
					return error(id, "save_custom_provider", err instanceof Error ? err.message : String(err));
				}
			}

			case "delete_custom_provider": {
				try {
					const providers = await deleteCustomProvider(command.providerId);
					await session.modelRegistry.refresh();
					return success(id, "delete_custom_provider", { ...providers, models: session.getAvailableModels() });
				} catch (err) {
					return error(id, "delete_custom_provider", err instanceof Error ? err.message : String(err));
				}
			}

			case "preview_custom_provider_models": {
				try {
					return success(id, "preview_custom_provider_models", await previewCustomProviderModels(command.data));
				} catch (err) {
					return error(id, "preview_custom_provider_models", err instanceof Error ? err.message : String(err));
				}
			}

			case "validate_custom_provider_connection": {
				try {
					return success(id, "validate_custom_provider_connection", await validateCustomProviderConnection(command.data));
				} catch (err) {
					return error(id, "validate_custom_provider_connection", err instanceof Error ? err.message : String(err));
				}
			}

			// =================================================================
			// Thinking
			// =================================================================

			case "set_thinking_level": {
				session.setThinkingLevel(command.level);
				return success(id, "set_thinking_level");
			}

			case "cycle_thinking_level": {
				const level = session.cycleThinkingLevel();
				if (!level) {
					return success(id, "cycle_thinking_level", null);
				}
				return success(id, "cycle_thinking_level", { level });
			}

			// =================================================================
			// Queue Modes
			// =================================================================

			case "set_steering_mode": {
				session.setSteeringMode(command.mode);
				return success(id, "set_steering_mode");
			}

			case "set_follow_up_mode": {
				session.setFollowUpMode(command.mode);
				return success(id, "set_follow_up_mode");
			}

			case "set_interrupt_mode": {
				session.setInterruptMode(command.mode);
				return success(id, "set_interrupt_mode");
			}

			// =================================================================
			// Compaction
			// =================================================================

			case "compact": {
				const result = await session.compact(command.customInstructions);
				return success(id, "compact", result);
			}

			case "set_auto_compaction": {
				session.setAutoCompactionEnabled(command.enabled);
				return success(id, "set_auto_compaction");
			}

			// =================================================================
			// Retry
			// =================================================================

			case "set_auto_retry": {
				session.setAutoRetryEnabled(command.enabled);
				return success(id, "set_auto_retry");
			}

			case "abort_retry": {
				session.abortRetry();
				return success(id, "abort_retry");
			}

			// =================================================================
			// Bash
			// =================================================================

			case "bash": {
				const bashCommand = command.command ?? readString(command.data, "command") ?? "";
				const result = await session.executeBash(bashCommand);
				return success(id, "bash", result);
			}

			case "abort_bash": {
				session.abortBash();
				return success(id, "abort_bash");
			}

			// =================================================================
			// Session
			// =================================================================

			case "get_session_stats": {
				const stats = session.getSessionStats();
				return success(id, "get_session_stats", stats);
			}

			case "export_html": {
				const path = await session.exportToHtml(command.outputPath);
				return success(id, "export_html", { path });
			}

			case "switch_session": {
				const sessionPath = command.sessionPath ?? readString(command.data, "sessionPath") ?? "";
				const cancelled = !(await session.switchSession(sessionPath));
				return success(id, "switch_session", { cancelled });
			}

			case "list_sessions": {
				const all = typeof command.all === "boolean" ? command.all : readBoolean(command.data, "all") ?? false;
				const sessions = await scopedSessions(all);
				const limit = command.limit ?? readNumber(command.data, "limit") ?? 40;
				return success(id, "list_sessions", { sessions: sessions.slice(0, limit).map(sessionInfo) });
			}

			case "get_session_tree": {
				return success(id, "get_session_tree", { tree: session.sessionManager.getTree() });
			}

			case "navigate_tree": {
				const result = await session.navigateTree(command.entryId, { summarize: command.summarize });
				return success(id, "navigate_tree", result);
			}

			case "branch": {
				const result = await session.branch(command.entryId);
				return success(id, "branch", { text: result.selectedText, cancelled: result.cancelled });
			}

			case "get_branch_messages": {
				const messages = session.getUserMessagesForBranching();
				return success(id, "get_branch_messages", { messages });
			}

			case "get_last_assistant_text": {
				const text = session.getLastAssistantText();
				return success(id, "get_last_assistant_text", { text });
			}

			case "set_session_name": {
				const name = command.name.trim();
				if (!name) {
					return error(id, "set_session_name", "Session name cannot be empty");
				}
				const applied = await session.setSessionName(name, "user");
				if (!applied) {
					return error(id, "set_session_name", "Session name cannot be empty");
				}
				return success(id, "set_session_name");
			}

			case "handoff": {
				const result = await session.handoff(command.customInstructions);
				return success(id, "handoff", result ? { savedPath: result.savedPath } : null);
			}

			// =================================================================
			// Messages
			// =================================================================

			case "get_messages": {
				return success(id, "get_messages", { messages: session.messages });
			}

			case "get_subagents": {
				return success(id, "get_subagents", { subagents: [...subagents.values()] });
			}

			case "get_subagent_transcript": {
				const subagentId = command.subagentId ?? readString(command.data, "subagentId") ?? "";
				const fromByte = command.fromByte ?? readNumber(command.data, "fromByte") ?? 0;
				const subagent = subagents.get(subagentId);
				if (!subagent?.sessionFile) return error(id, "get_subagent_transcript", `Unknown subagent transcript: ${subagentId}`);
				return success(id, "get_subagent_transcript", {
					subagentId,
					sessionFile: subagent.sessionFile,
					...readSubagentTranscript(subagent.sessionFile, fromByte),
				});
			}

			case "get_tools": {
				const active = new Set(session.getActiveToolNames());
				return success(id, "get_tools", {
					tools: session.getAllToolNames().map(name => {
						const tool = session.getToolByName(name);
						return {
							name,
							description: tool?.description,
							active: active.has(name),
						};
					}),
				});
			}

			case "get_active_tools": {
				return success(id, "get_active_tools", { toolNames: session.getActiveToolNames() });
			}

			case "set_active_tools": {
				const toolNames = Array.isArray(command.toolNames) ? command.toolNames : readStringArray(command.data, "toolNames");
				await session.setActiveToolsByName(toolNames);
				return success(id, "set_active_tools", { toolNames: session.getActiveToolNames() });
			}

			case "get_approval_mode": {
				return success(id, "get_approval_mode", { mode: session.settings.get("tools.approvalMode") });
			}

			case "set_approval_mode": {
				const mode = command.mode ?? readString(command.data, "mode") ?? "read-allow";
				if (!["ask", "read-allow", "bypass", "always-ask", "write", "yolo"].includes(mode)) {
					return error(id, "set_approval_mode", `Invalid approval mode: ${mode}`);
				}
				session.settings.override("tools.approvalMode", mode);
				return success(id, "set_approval_mode", { mode });
			}

			// =================================================================
			// Native UI Metadata
			// =================================================================

			case "get_slash_commands": {
				const builtin = BUILTIN_SLASH_COMMAND_DEFS.map(command => ({
					name: command.name,
					description: command.description,
					source: "builtin" as const,
					inlineHint: command.inlineHint,
					subcommands: command.subcommands,
				}));
				const file = session.slashCommands.map(command => ({
					name: command.name,
					description: command.description,
					source: "file" as const,
					path: command.source,
				}));
				const skills = session.skills
					.filter(skill => !skill.hide)
					.map(skill => ({
						name: `skill:${skill.name}`,
						description: skill.description,
						source: "skill" as const,
						path: skill.filePath,
					}));
				const extension = session.customCommands.map(command => ({
					name: command.name,
					description: command.description,
					source: "extension" as const,
				}));
				return success(id, "get_slash_commands", { commands: [...builtin, ...file, ...skills, ...extension] });
			}

			case "expand_slash_command": {
				return success(id, "expand_slash_command", { text: expandSlashCommand(command.text, [...session.slashCommands]) });
			}

			case "get_skills": {
				return success(id, "get_skills", {
					skills: session.skills
						.filter(skill => !skill.hide)
						.map(skill => ({
							name: skill.name,
							description: skill.description,
							path: skill.filePath,
							source: skill.source,
						})),
				});
			}

			case "build_skill_prompt": {
				const skill = session.skills.find(skill => skill.name === command.name);
				if (!skill) return error(id, "build_skill_prompt", `Unknown skill: ${command.name}`);
				const skillArgs = typeof command.args === "string" ? command.args : readString(command.data, "args") ?? "";
				return success(id, "build_skill_prompt", await buildSkillPromptMessage(skill, skillArgs));
			}

			case "get_prompt_templates": {
				return success(id, "get_prompt_templates", {
					templates: session.promptTemplates.map(template => ({
						name: template.name,
						description: template.description,
						path: template.source,
					})),
				});
			}

			case "get_history_recent": {
				return success(id, "get_history_recent", { entries: historyEntries(HistoryStorage.open().getRecent(command.limit ?? 20, session.sessionManager.getCwd())) });
			}

			case "search_history": {
				return success(id, "search_history", { entries: historyEntries(HistoryStorage.open().search(command.query, command.limit ?? 20, session.sessionManager.getCwd())) });
			}

			// =================================================================
			// Login
			// =================================================================

			case "get_login_providers": {
				const providers = getOAuthProviders().map(provider => ({
					id: provider.id,
					name: provider.name,
					available: provider.available,
					authenticated: session.modelRegistry.authStorage.hasAuth(authProviderId(provider.id)),
					authProviderId: authProviderId(provider.id),
					modelProviderId: modelProviderId(provider.id),
					availableModelCount: session.getAvailableModels().filter(model => model.provider === modelProviderId(provider.id)).length,
				}));
				return success(id, "get_login_providers", { providers });
			}

			case "login": {
				const knownProvider = getOAuthProviders().find(p => p.id === command.providerId);
				if (!knownProvider) {
					return error(id, "login", `Unknown OAuth provider: ${command.providerId}`);
				}
				const uiCtx = new RpcExtensionUIContext(pendingExtensionRequests, output);
				session.modelRegistry.authStorage
					.login(command.providerId, {
						onAuth: info => {
							output({
								type: "extension_ui_request",
								id: Snowflake.next() as string,
								method: "open_url",
								url: info.url,
								instructions: info.instructions,
							} as RpcExtensionUIRequest);
						},
						onProgress: message => {
							uiCtx.notify(message, "info");
						},
						onPrompt: prompt =>
							uiCtx.loginInput(prompt).then(value => {
								if (value === undefined && !prompt.allowEmpty) throw new Error("Login prompt cancelled");
								return value ?? "";
							}),
					})
					.then(async () => {
						await session.modelRegistry.refresh();
						output(success(id, "login", { providerId: command.providerId }));
					})
					.catch((err: unknown) => {
						output(error(id, "login", err instanceof Error ? err.message : String(err)));
					});
				return success(id, "login", { providerId: command.providerId, pending: true });
			}

			default: {
				const unknownCommand = command as { type: string };
				return error(undefined, unknownCommand.type, `Unknown command: ${unknownCommand.type}`);
			}
		}
	};

	function authProviderId(providerId: string): string {
		return providerId === "openai-codex-device" ? "openai-codex" : providerId;
	}

	function modelProviderId(providerId: string): string {
		return providerId === "openai-codex-device" ? "openai-codex" : providerId;
	}

	function historyEntries(entries: ReturnType<HistoryStorage["getRecent"]>) {
		return entries.map(entry => ({ id: entry.id, prompt: entry.prompt, createdAt: entry.created_at, cwd: entry.cwd }));
	}

	function sessionInfo(info: SessionInfo) {
		return {
			path: info.path,
			id: info.id,
			cwd: info.cwd,
			title: info.title,
			firstMessage: info.firstMessage,
			messageCount: info.messageCount,
			size: info.size,
			created: info.created.toISOString(),
			modified: info.modified.toISOString(),
		};
	}

	async function scopedSessions(includeLegacy: boolean): Promise<SessionInfo[]> {
		const current = await SessionManager.list(session.sessionManager.getCwd(), session.sessionManager.getSessionDir());
		if (!includeLegacy && current.length > 0) return current;
		const legacyRoot = `${agentDir}/sessions`;
		const legacy = await SessionManager.list(session.sessionManager.getCwd(), legacyRoot);
		const byPath = new Map<string, SessionInfo>();
		for (const item of [...current, ...legacy]) byPath.set(item.path, item);
		return [...byPath.values()].sort((a, b) => b.modified.getTime() - a.modified.getTime());
	}

	function readString(value: unknown, key: string): string | undefined {
		if (!value || typeof value !== "object") return undefined;
		const record = value as Record<string, unknown>;
		return typeof record[key] === "string" ? record[key] : undefined;
	}

	function readBoolean(value: unknown, key: string): boolean | undefined {
		if (!value || typeof value !== "object") return undefined;
		const record = value as Record<string, unknown>;
		return typeof record[key] === "boolean" ? record[key] : undefined;
	}

	function readNumber(value: unknown, key: string): number | undefined {
		if (!value || typeof value !== "object") return undefined;
		const record = value as Record<string, unknown>;
		return typeof record[key] === "number" ? record[key] : undefined;
	}

	function readStringArray(value: unknown, key: string): string[] {
		if (!value || typeof value !== "object") return [];
		const record = value as Record<string, unknown>;
		return Array.isArray(record[key]) ? record[key].filter(item => typeof item === "string") : [];
	}

	function isSecretPrompt(message = "", placeholder = ""): boolean {
		const text = `${message} ${placeholder}`.toLowerCase();
		return text.includes("api key") || text.includes("token") || text.includes("secret") || text.includes("password");
	}

	/**
	 * Check if shutdown was requested and perform shutdown if so.
	 * Called after handling each command when waiting for the next command.
	 */
	async function checkShutdownRequested(): Promise<void> {
		if (!shutdownState.requested) return;

		if (session.extensionRunner?.hasHandlers("session_shutdown")) {
			await session.extensionRunner.emit({ type: "session_shutdown" });
		}

		process.exit(0);
	}

	// Listen for JSON input using Bun's stdin
	for await (const parsed of readJsonl(Bun.stdin.stream())) {
		try {
			// Handle extension UI responses
			if ((parsed as RpcExtensionUIResponse).type === "extension_ui_response") {
				const response = parsed as RpcExtensionUIResponse;
				const pending = pendingExtensionRequests.get(response.id);
				if (pending) {
					pending.resolve(response);
				}
				continue;
			}

			if (isRpcHostToolResult(parsed)) {
				hostToolBridge.handleResult(parsed);
				continue;
			}

			if (isRpcHostToolUpdate(parsed)) {
				hostToolBridge.handleUpdate(parsed);
				continue;
			}

			if (isRpcHostUriResult(parsed)) {
				hostUriBridge.handleResult(parsed);
				continue;
			}

			// Handle regular commands
			const command = parsed as RpcCommand;
			const response = await handleCommand(command);
			output(response);

			// Check for deferred shutdown request (idle between commands)
			await checkShutdownRequested();
		} catch (e: any) {
			output(error(undefined, "parse", `Failed to parse command: ${e.message}`));
		}
	}

	// stdin closed — RPC client is gone, exit cleanly
	hostToolBridge.rejectAllPending("RPC client disconnected before host tool execution completed");
	hostUriBridge.clear("RPC client disconnected before host URI request completed");
	process.exit(0);
}
