# Kaji Agent Runtime Map

Date: 2026-06-06

## Scope

This document maps the native `KajiAgentRuntime` path used by Kaji's built-in agent surface. It does not cover terminal-native external agent integrations under `Kaji/Services/CodingAgents/`.

## Native RPC Boot

1. Kaji launches the runtime through `KajiAgentProcess` after readiness is resolved by `KajiAgentRuntimeReadinessController`.
2. Source builds execute `KajiAgentRuntime/src/kaji-rpc.ts` with Bun.
3. Packaged builds execute bundled `kaji-agent-runtime.mjs` from Kaji's SwiftPM resources.
4. `kaji-rpc.ts` sets Kaji runtime environment, parses RPC args, initializes `Settings`, applies the `kaji-rpc-build` runtime profile defaults, initializes auth/model/session services, creates an `AgentSession`, then runs `runRpcMode()`.

## Runtime Profile

`KajiAgentRuntime/src/runtime/profile.ts` is the first declarative profile layer. `kajiRpcRuntimeProfile()` captures the current production RPC baseline:

- Mode: `rpc`.
- Permission posture: `read-allow`.
- Default visible tool patterns: read, bash, edit, resolve, task, todo, find/search, LSP, browser.
- Default hidden tool patterns: yield, findings, tool issue reporting, goal.
- Default settings reset list: todo, async, bash backgrounding, task isolation/concurrency, disabled providers, and memory defaults.

`applyRpcDefaultSettingOverrides()` delegates to this profile so future runtime policies can move out of `main.ts` without changing current behavior.

## Session Construction

`createAgentSession()` in `KajiAgentRuntime/src/sdk.ts` constructs the runtime:

1. Discovers auth/model registry/settings.
2. Loads context files, skills, rules, custom commands, and prompt templates.
3. Builds built-in, extension, custom, and MCP tools.
4. Builds the system prompt through `buildSystemPrompt()`.
5. Creates `AgentSession` with prompt rebuild hooks, tool registry hooks, MCP refresh hooks, LSP startup, extension hooks, task identity, Hindsight state, and client bridge access.

## Prompt Pipeline

`KajiAgentRuntime/src/system-prompt.ts` renders the main prompt from:

- Base Kaji Agent system template.
- Optional custom and append prompts.
- Context files from capability providers.
- Skills and rules.
- Workspace tree and git state.
- Tool metadata.
- MCP server instructions and discovery state.
- Kaji/runtime date, cwd, and environment data.

The prompt is rebuilt when active tool names, discoverable tools, MCP instructions, memory state, or extension hooks change.

## Tool Pipeline

`KajiAgentRuntime/src/tools/index.ts` owns the built-in catalog. Tool creation now routes requested tool names through `resolveToolNames()` in `KajiAgentRuntime/src/tools/tool-resolver.ts`, which supports exact names, glob patterns, deprecated aliases, dedupe, and requested order.

Built-in visible tools include read, bash, edit, AST tools, browser, task, job, todo, web search, GitHub, LSP, eval, SSH, checkpoints, recipes, image inspection, mermaid rendering, and Hindsight memory tools.

Hidden tools include yield, resolve, goal, report finding, and report tool issue.

## Subagent Pipeline

`KajiAgentRuntime/src/task/index.ts` exposes the `task` tool. `KajiAgentRuntime/src/task/executor.ts` creates child sessions with subagent-specific prompts, tool limits, depth, isolation settings, output schemas, yield requirements, artifact managers, shared eval kernels, IRC identity, and task progress reporting.

Bundled agents live in `KajiAgentRuntime/src/task/agents.ts` and include general work, exploration, planning, review, design, and research roles.

## Native Host Bridge

Swift host tools are defined in `Kaji/Services/KajiAgentHostToolCatalog.swift` and executed by `Kaji/Services/KajiAgentHostToolRegistry.swift`.

Current host tools:

- `kaji_get_active_context`.
- `kaji_open_file`.
- `kaji_open_terminal`.
- `kaji_fff_find`.
- `kaji_fff_search`.

File URI reads route through `KajiAgentHostURIResolver` and `KajiAgentWorkspacePathResolver` so workspace boundaries are enforced outside the UI store.

## Runtime Events

`AgentSessionEvent` in `KajiAgentRuntime/src/session/agent-session.ts` feeds the native UI through RPC mode. Swift normalizes runtime state through:

- `KajiAgentRuntimeStateSnapshot`.
- `KajiAgentTimeline`.
- `KajiAgentAssistantTimelineApplier`.
- `KajiAgentToolTimelineApplier`.
- `KajiAgentTranscriptRestorer`.
- `KajiAgentTodoWriteUpdate`.
- `KajiAgentExtensionRequestParser`.

Important runtime event families include tool calls, assistant output, todo updates, task progress, compaction, retry, notices, thinking-level changes, and goal updates.

## Next Split Targets

1. Split session prompting, compaction, retry, permissions, tool registry, MCP discovery, todo reminders, eval lifecycle, and subagent event aggregation out of `agent-session.ts`.
2. Split `sdk.ts` into session context, tool building, prompt building, MCP setup, extension setup, and LSP setup.
3. Move built-in and hidden tool catalogs, gates, resolver, and discovery policy out of `tools/index.ts`.
4. Route all approval flows through a central permission service.
5. Add native Kaji code graph tools through the host bridge.
