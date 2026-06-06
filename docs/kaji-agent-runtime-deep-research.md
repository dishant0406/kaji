# KajiAgentRuntime Harness Deep Research

Date: 2026-06-06
Scope: `KajiAgentRuntime` only, plus the native Swift bridge that embeds it (`KajiAgent*` RPC/host-tool files). This intentionally does not analyze Kaji's generic terminal-agent integrations under `Kaji/Services/CodingAgents/` except where architecture docs distinguish them from the native runtime.

## Sources Reviewed

### Kaji local sources

- Code graph report: `/Users/dishants/.kaji/extensions/kajicodegraph/projects/F7F94EF1-A03B-471A-8EB7-F4CBE7B66E7F/8594EB89-49B4-4AEF-9158-A3A05220BF28/graphify-out/GRAPH_REPORT.md`.
- Architecture contract: `docs/architecture.md`, especially the Kaji Agent runtime paragraph around native chat, runtime process, event timeline, transcript restoration, todo updates, host tools, URI resolution, and workspace-boundary enforcement.
- Runtime entry: `KajiAgentRuntime/src/kaji-rpc.ts`.
- Runtime defaults/CLI: `KajiAgentRuntime/src/main.ts`.
- Session loop: `KajiAgentRuntime/src/session/agent-session.ts`.
- SDK/session construction: `KajiAgentRuntime/src/sdk.ts`.
- Prompt builder: `KajiAgentRuntime/src/system-prompt.ts` and `KajiAgentRuntime/src/prompts/system/*.md`.
- Tool catalog/factory: `KajiAgentRuntime/src/tools/index.ts`.
- Subagent harness: `KajiAgentRuntime/src/task/index.ts`, `KajiAgentRuntime/src/task/executor.ts`, `KajiAgentRuntime/src/task/agents.ts`, `KajiAgentRuntime/src/task/worktree.ts`.
- Swift host bridge: `Kaji/Services/KajiAgentHostToolCatalog.swift`, `Kaji/Services/KajiAgentHostToolRegistry.swift`, `Kaji/Services/KajiAgentProcess.swift`, `Kaji/Models/KajiAgentRPCModels.swift`.

### External sources

- ForgeCode website: https://forgecode.dev/
- ForgeCode source clone: `https://github.com/tailcallhq/forgecode`, local clone `/tmp/kaji-harness-research/forgecode`, commit `40e3ba1` from 2026-06-06.
- Forge/ACP wrapper note: `https://github.com/forge-agents/forge` is a different ACP terminal interface forked from OpenCode, not the ForgeCode harness source analyzed here.
- OpenCode source clone: `https://github.com/sst/opencode` / `https://github.com/anomalyco/opencode`, local clone `/tmp/kaji-harness-research/opencode-sst`, commit `1399323` from 2026-06-06.
- OpenCode docs: https://opencode.ai/docs/tools/ and https://opencode.ai/docs/agents/.
- DeepWiki OpenCode agent-system index, used only as a navigational secondary source: https://deepwiki.com/sst/opencode/3.2-agents-and-rules.

## Executive Conclusion

KajiAgentRuntime is already much closer to ForgeCode/OpenCode-class harness quality than the generic Kaji terminal-agent layer. It already has a real agent loop, strong prompts, rich tools, subagents, MCP, tool discovery, todo state, plan mode, compaction, retry, LSP, browser, Hindsight memory, and a native Swift host-tool bridge.

The biggest gaps are not "missing a coding agent loop". The gaps are:

1. **Runtime architecture is too monolithic.** `agent-session.ts` is ~8,950 LOC and `sdk.ts` is ~2,214 LOC. The code contains many excellent capabilities but they are hard to audit, test, evolve, and expose consistently.
2. **Policy is scattered.** ForgeCode has clear agent/profile fields such as max requests, max tool failures, retry, compaction, timeout, and tool lists. Kaji has similar pieces, but not one first-class runtime profile object that explains the harness behavior.
3. **Permission handling should be unified.** Kaji has ACP permission gates, extension approval wrappers, settings approval modes, and Swift host approvals. OpenCode's permission service is cleaner: one ruleset system, one pending request store, one reply path, wildcard matching, and session/persistent allow behavior.
4. **Tool selection should be more declarative.** Kaji has `createTools()` and discovery modes, but Forge's glob/alias tool resolver and OpenCode's permission-driven tool disabling are easier to reason about.
5. **Kaji-specific code intelligence should be native.** Kaji has a code graph system outside the runtime, but `KajiAgentRuntime` does not expose first-class code graph tools like `code_graph_search`, `code_graph_neighbors`, or `code_graph_report`.
6. **Prompt and tool quality should be snapshot-tested.** Forge has prompt/system-context snapshots. Kaji's prompts are strong but generated dynamically from many inputs; golden tests would prevent regressions.
7. **Native bridge tools are too small.** Swift host tools currently cover active context, opening files/terminals, and FFF search. This is useful, but Kaji's native app can provide much richer high-signal context than a terminal-only harness.

## Current KajiAgentRuntime Inventory

### Runtime entry and embedding

`KajiAgentRuntime/src/kaji-rpc.ts` is a Bun RPC entrypoint for the native Kaji Agent surface. It sets Kaji-specific runtime environment, defaults the agent dir to `~/Library/Application Support/Kaji/AgentRuntime`, parses arguments with RPC defaults, initializes settings/auth/model registry/session manager, then calls `createAgentSession()` and `runRpcMode()`.

Key Kaji RPC behavior:

- `PI_CONFIG_DIR=.kaji/agent-runtime`.
- `PI_NOTIFICATIONS=off` and `PI_NO_TITLE=1` for embedded use.
- Default approval mode is `read-allow`.
- `applyRpcDefaultSettingOverrides(settings)` resets several CLI-default features for RPC hosts.
- MCP is opt-in via `KAJI_AGENT_ENABLE_MCP=1`.

`docs/architecture.md` says the native Kaji Agent surface is backed by `KajiAgentHome`, `KajiAgentStore`, `KajiAgentProcess`, `KajiAgentPendingRPC`, `KajiAgentRuntimeReadinessController`, and `KajiAgentRuntimeLocator`, and that source builds run `KajiAgentRuntime/src/kaji-rpc.ts` while packaged builds run `kaji-agent-runtime.mjs` from the SwiftPM resource bundle.

### Runtime defaults

`KajiAgentRuntime/src/main.ts` defines `RPC_DEFAULTED_SETTING_PATHS` and `applyRpcDefaultSettingOverrides()`. For RPC/native embedding, it resets:

- Todo settings.
- Async jobs.
- Bash auto-background settings.
- Task isolation/concurrency/recursion settings.
- Disabled providers.
- Memory backend and memories.

This is good because Kaji controls the host UX, but it also means Kaji needs a clear, documented runtime profile so future changes do not accidentally diverge from the native host assumptions.

### Session loop

`KajiAgentRuntime/src/session/agent-session.ts` is the center of the harness. It is very powerful, but too large.

It owns or coordinates:

- `AgentSessionEvent`, including base agent events plus Kaji/runtime-specific events such as `auto_compaction_start`, `auto_compaction_end`, `auto_retry_start`, `auto_retry_end`, `retry_fallback_applied`, `retry_fallback_succeeded`, `todo_reminder`, `todo_auto_clear`, `irc_message`, `notice`, `thinking_level_changed`, and `goal_updated`.
- Prompt execution and follow-up steering.
- Tool registry refresh.
- Hidden messages and deferred messages.
- System-prompt rebuilds.
- ACP bridge and permission decision flow.
- Compaction, auto-compaction, handoff, and context overflow recovery.
- Retry and fallback models.
- Todo reminder state.
- Task/subagent progress and usage aggregation.
- Eval kernel lifecycle.
- Extension hooks.
- MCP discovered tool activation.
- Background jobs and IRC coordination.

This is the biggest architecture risk in KajiAgentRuntime. It is doing too many jobs in one file.

### SDK/session construction

`KajiAgentRuntime/src/sdk.ts` is also highly capable. It accepts options for:

- Custom system prompt and append prompt.
- Custom tools/extensions.
- Skills/rules/context files/workspace tree/prompt templates/slash commands.
- MCP enablement and discovery.
- LSP enablement.
- Tool names and output schema.
- Yield requirements for subagents.
- Task depth and parent Hindsight.
- Agent identity/display name.
- Auth/model registry/settings.
- Runtime prompt rebuild and tool refresh.

Important strong point: every tool is wrapped through extension/approval infrastructure, and comments in the code explicitly protect the approval path from disappearing when no extensions are present.

### Prompt system

`KajiAgentRuntime/src/system-prompt.ts` builds the main system prompt from:

- Base templates in `src/prompts/system/`.
- Context files loaded via capabilities.
- Skills and rules.
- Workspace tree and git context.
- Tool metadata.
- MCP server instructions.
- System info and current date.
- Custom system prompt and append prompt.

Strong prompt features already present:

- Kaji Agent identity as a coding harness.
- Staff-engineer posture.
- Strong instruction to inspect code before editing.
- Tool inventory section with descriptions.
- Explicit tool-use guidance for read/search/LSP/AST/browser/task/web search.
- Special URL schemes: `skill://`, `rule://`, `memory://`, `agent://`, `artifact://`, `local://`, and optional provider schemes.
- Explicit "do not search for AGENTS/CLAUDE again if context is loaded" guidance.
- Eager todo prompt for substantive work.
- Plan-mode prompt with read-only constraints and `resolve` action.
- Subagent prompt requiring `yield` completion.
- Web-search prompt focused on primary sources, recency, and attribution.

### Tool catalog

`KajiAgentRuntime/src/tools/index.ts` exposes built-ins:

- File/search/edit: `read`, `find`, `search`, `edit`, `write`, `ast_grep`, `ast_edit`.
- Execution: `bash`, `recipe`, `eval`, `ssh`, `debug`.
- UX/native: `browser`, `inspect_image`, `render_mermaid`, `ask`.
- Agent control: `task`, `job`, `irc`, `todo_write`, `resolve`, `goal`, `checkpoint`, `rewind`.
- External/research: `github`, `web_search`, `search_tool_bm25`.
- Memory: `retain`, `recall`, `reflect` when Hindsight is active.
- Hidden/review: `yield`, `report_finding`, `report_tool_issue`.

Tool creation has useful smart behavior:

- Defaults to `read`, `bash`, `edit` as essentials.
- Auto-includes AST tools when text search/edit is requested and settings allow it.
- Enables `search_tool_bm25` for tool discovery.
- Limits task recursion by `task.maxRecursionDepth`.
- Always adds `resolve` when missing.
- Adds auto-QA reporting tool when enabled.

### Subagents/tasks

Kaji's task system is rich:

- Bundled agents like `task`, `explore`, `oracle`, `librarian`, `plan`, `reviewer`, and `designer`.
- In-process subagent execution.
- Optional isolated worktrees.
- Sync and async jobs.
- Output schemas and validation.
- `yield` completion requirement.
- Agent output artifacts via `agent://`.
- IRC peer messaging.
- Parent context forwarding.
- Shared eval kernels.
- Task progress snapshots for UI.

This is an area where Kaji is already ahead of basic OpenCode, but the control surface is more complex than OpenCode's simpler `general`/`explore` model.

### Native Swift bridge

Current host tools in `KajiAgentHostToolCatalog.swift`:

- `kaji_get_active_context`.
- `kaji_open_file`.
- `kaji_open_terminal`.
- `kaji_fff_find`.
- `kaji_fff_search`.

Current bridge strengths:

- Workspace path resolution happens outside the UI store.
- Native FFF search can be faster and more accurate than generic shell search.
- Tool definitions include approval categories.

Current bridge limitation:

- It does not yet expose Kaji's unique native assets: code graph, editor selection, open tabs, diagnostics, terminal panes, git/worktree UI state, recent files, project graph summaries, or native diff/review affordances.

## ForgeCode Research

ForgeCode positions itself as a high-performing coding harness with codebase understanding, model specialization, bounded multi-agent context, and evaluation-driven shipping. The homepage explicitly emphasizes codebase understanding, model-per-task selection, specialized subagents for research/planning/execution, and extensive evaluations.

### Source architecture highlights

Analyzed source: `/tmp/kaji-harness-research/forgecode`, commit `40e3ba1`.

Key files:

- `crates/forge_app/src/system_prompt.rs`.
- `crates/forge_domain/src/system_context.rs`.
- `crates/forge_domain/src/agent.rs`.
- `crates/forge_domain/src/tools/catalog.rs`.
- `crates/forge_app/src/tool_resolver.rs`.
- `crates/forge_config/.forge.toml`.
- `crates/forge_app/src/orch_spec/snapshots/*.snap`.

### ForgeCode prompt/context model

Forge builds a typed `SystemContext` with fields for:

- Environment.
- Tool information.
- Whether tools are supported.
- Files.
- Custom rules.
- Parallel tool-call support.
- Skills.
- Model.
- `tool_names` map filtered to tools available for the current agent.
- File-extension statistics from `git ls-files`.
- Agents.
- Template config.

Kaji has similar ingredients, but Forge's typed context object is cleaner and easier to snapshot-test.

### ForgeCode tool system

Forge native tools include:

- `read`, `write`, `fs_search`, `sem_search`, `remove`, `patch`, `multi_patch`, `undo`, `shell`, `fetch`, `followup`, `plan`, `skill`, `todo_write`, `todo_read`, `task`.

Notable differences from Kaji:

- `sem_search` is a first-class tool, not just a discovery mode.
- `todo_read` is separate from `todo_write`.
- `undo` is a first-class tool.
- `multi_patch` is a first-class batch edit tool.
- Tool descriptions live as separate markdown files and are templated with config values.

Kaji already has more total tools, but Forge has a tighter default set and stronger declarative control.

### ForgeCode agent model

Forge `Agent` includes:

- ID/title/description.
- Provider/model.
- System prompt and user prompt templates.
- Tool list.
- Max turns.
- Compaction config.
- Custom rules.
- Temperature/top-p/top-k/max tokens.
- Reasoning config.
- `max_tool_failure_per_turn`.
- `max_requests_per_turn`.

This is an important lesson for Kaji: make runtime harness behavior a first-class profile/agent object instead of spreading it across settings, constructors, prompt builder, and session internals.

### ForgeCode tool resolver

Forge has a dedicated `ToolResolver` with:

- Exact tool names.
- Glob patterns like `fs_*`.
- Deprecated aliases.
- Deduplication.
- Agent-defined ordering.

Kaji's `createTools()` has many decisions embedded directly in the factory. It should get a Forge-style resolver layer.

### ForgeCode defaults

Forge defaults in `.forge.toml` include:

- `max_requests_per_turn = 100`.
- `max_tool_failure_per_turn = 3`.
- `max_parallel_file_reads = 64`.
- `max_read_lines = 2000`.
- `tool_timeout_secs = 300`.
- `verify_todos = true`.
- `subagents = true`.
- Retry status codes and max attempts.
- Compaction thresholds and retention windows.

Kaji has many equivalent controls, but not grouped into one readable Kaji RPC runtime profile.

## OpenCode Research

OpenCode is the active SST/Anomaly TypeScript coding agent. The current repository is `github.com/anomalyco/opencode` (also reachable from `github.com/sst/opencode`). Its README states it includes built-in `build` and `plan` agents, plus a `general` subagent. OpenCode docs also document wildcard permissions across built-ins, custom tools, and MCP tools.

Analyzed source: `/tmp/kaji-harness-research/opencode-sst`, commit `1399323`.

Key files:

- `packages/opencode/src/agent/agent.ts`.
- `packages/opencode/src/session/tools.ts`.
- `packages/opencode/src/session/instruction.ts`.
- `packages/opencode/src/session/llm.ts`.
- `packages/opencode/src/session/reminders.ts`.
- `packages/opencode/src/permission/index.ts`.
- `packages/opencode/src/tool/registry.ts`.
- `packages/opencode/src/tool/read.ts`.
- `packages/opencode/src/tool/edit.ts`.
- `packages/opencode/src/tool/task.ts`.
- `packages/opencode/src/tool/lsp.ts`.
- `packages/opencode/src/session/prompt/*.txt`.

### OpenCode agents and modes

OpenCode's native agents:

- `build`: default development agent.
- `plan`: read-only planning agent with edits denied except plan files.
- `general`: subagent for complex research/multi-step work.
- `explore`: fast subagent specialized for codebase exploration.
- Hidden system agents: `compaction`, `title`, `summary`.

Kaji already has more bundled agents, but OpenCode's split is very understandable and easy to explain in UI. Kaji should keep its richer system but expose a small first-class surface: Build, Plan, Explore, Review, Research.

### OpenCode permission system

OpenCode has a central `Permission.Service`:

- Rules are matched by wildcard over permission name and pattern.
- Rulesets merge from defaults, agent config, and session config.
- Requests emit `permission.asked` events.
- Replies emit `permission.replied` events.
- Pending requests are stored centrally.
- Replies support one-time and always/persistent approvals.
- Rejecting one request rejects other pending requests in the same session.
- Permissions can target MCP tools with wildcards like `mymcp_*`.

This is cleaner than Kaji's current distributed approval paths.

### OpenCode instruction/context loading

OpenCode `session/instruction.ts` loads:

- Global `AGENTS.md`.
- Optional `~/.claude/CLAUDE.md`.
- Project `AGENTS.md`, `CLAUDE.md`, or deprecated `CONTEXT.md`, with first project-level match semantics.
- Configured instruction files/URLs.
- Nearby instruction files when reading files, avoiding duplicates.

Kaji's capability-based context loader is more flexible and already supports multiple agent ecosystems, but OpenCode's "nearby instruction file on read" is worth copying if Kaji does not already do this at read-time.

### OpenCode tool registry

OpenCode built-ins include:

- `shell`, `read`, `glob`, `grep`, `edit`, `write`, `task`, `fetch`, `todo`, `search`, `skill`, `patch`, optional `lsp`, optional plan tools, and plugin/MCP tools.

The registry dynamically describes task and skill tools based on the active agent and available skills. It also switches edit strategy based on model family: some GPT models get `apply_patch` instead of `edit`/`write`.

Kaji can adopt the idea of model-profile-specific tool surfaces more explicitly. Kaji has `ToolChoice` and model-specific caps but not a simple visible profile rule like "this model gets patch, this model gets edit".

### OpenCode read/edit safety

OpenCode's `read` tool:

- Supports line ranges.
- Limits reads to 2,000 lines and 50 KB by default.
- Detects binary files.
- Warms LSP.
- Loads nearby instruction files.
- Handles images/PDF-like attachments.

OpenCode's `edit` tool:

- Uses exact old/new string replacement.
- Locks files during edits.
- Preserves BOM and line endings.
- Requires permission with diff metadata.
- Publishes file-system/watch events.
- Runs formatting.
- Touches LSP and reports diagnostics after edits.

Kaji's hashline/edit stack is likely stronger in some ways, but Kaji should ensure these safety traits are explicit, uniform, and tested across `edit`, `write`, `ast_edit`, host tools, and plan-mode edits.

### OpenCode prompts

OpenCode has provider-specific prompts (`codex.txt`, `anthropic.txt`, `gemini.txt`) and small focused prompts for compaction, summary, title, max steps, plan mode, plan reminders, and build-switch reminders.

Kaji has one strong general prompt with templates and capability injection. The opportunity is not to copy OpenCode's prompt wholesale, but to split Kaji's prompt into composable, snapshot-tested modules:

- Core identity.
- Tool-use policy.
- Worktree safety.
- Planning policy.
- Subagent policy.
- Verification policy.
- UI/native bridge policy.
- Model/provider-specific deltas.

## Gap Analysis

| Area | KajiAgentRuntime today | Forge/OpenCode pattern | Recommended improvement |
|---|---|---|---|
| Runtime architecture | Very powerful but concentrated in `agent-session.ts` and `sdk.ts` | Smaller services: agents, permissions, tools, prompts, config | Split into focused runtime services before adding features |
| Runtime policy | Settings + constructor options + hardcoded RPC overrides | Forge agent/profile fields; OpenCode agent info and permissions | Add `RuntimeProfile` / `AgentProfile` object for Kaji RPC |
| Tool resolution | `createTools()` embeds factory, discovery, hidden tools, settings gates | Forge `ToolResolver`; OpenCode registry + permissions | Add `tools/tool-resolver.ts` with exact/glob/alias/order |
| Permissions | ACP gate + extension wrapper + settings + host approval | OpenCode central permission service | Add central `permissions/permission-service.ts` and route all approvals through it |
| Code intelligence | Search, find, AST, LSP, FFF host search, BM25 tool discovery | Forge first-class semantic search; OpenCode simple grep/glob/read | Add native Kaji code graph tools |
| Prompt composition | Strong but generated through broad `system-prompt.ts`/`sdk.ts` | Forge typed `SystemContext` + snapshots; OpenCode focused prompt files | Add typed `PromptContext` and golden snapshots |
| Plan mode | Has `resolve` and plan prompt | OpenCode writes only plan file and exits via plan tool | Keep Kaji plan mode but simplify UI path and add plan-file option |
| Subagents | Powerful, schema/yield/isolation/IRC/artifacts | Forge specialized roles; OpenCode simple `general`/`explore` | Add simple visible profiles over rich internals |
| Todo | Strong eager todo + reminders | Forge has `todo_read`/`todo_write` and `verify_todos`; OpenCode todo updates | Add `todo_read`; add todo verification policy with tests |
| Edit safety | Hashline/edit stack, write, AST edit | OpenCode exact edit + lock + diagnostics; Forge patch/multi-patch/undo | Add unified edit safety matrix and make `undo` first-class |
| Native host bridge | Active context, open file/terminal, FFF find/search | Desktop harnesses can expose richer editor/workspace state | Add host tools for selection, tabs, diagnostics, git/worktree, code graph |
| Observability | Event types and timeline appliers exist | Forge snapshots; OpenCode event bus and permission events | Normalize runtime event schema and snapshot Swift parsing |
| Config UX | Many settings | Forge `.forge.toml`; OpenCode `opencode.json` + markdown agents | Generate a Kaji runtime profile view/debug command |

## Improvement Plan

### Phase 0 — Freeze Current Behavior With Documentation and Snapshots

Goal: make KajiAgentRuntime safer to improve without regressions.

1. Add a `KajiAgentRuntime/docs/runtime-map.md` that documents the actual runtime pipeline:
   - `kaji-rpc.ts` -> settings/auth/model registry/session manager -> `createAgentSession()` -> `runRpcMode()` -> Swift RPC frames.
   - Tool construction path.
   - Prompt construction path.
   - Permission path.
   - Subagent path.
   - MCP/discovery path.
2. Add golden tests for rendered system prompts under these matrices:
   - default RPC.
   - plan mode.
   - todo eager mode.
   - MCP discovery enabled.
   - LSP enabled/disabled.
   - browser enabled.
   - subagent with `yield`.
   - web-search agent.
3. Add tool catalog snapshot tests:
   - default essential tools.
   - all tools.
   - discovery mode.
   - RPC profile.
   - task-depth limit.
   - Hindsight enabled.
4. Add Swift RPC schema fixtures for the most important runtime events:
   - tool start/end.
   - permission request/reply.
   - todo update.
   - task progress.
   - compaction start/end.
   - retry start/end.

### Phase 1 — Split The Monoliths

Goal: preserve behavior while making the codebase maintainable.

Refactor `KajiAgentRuntime/src/session/agent-session.ts` into focused files:

- `session/agent-session.ts`: public facade and state wiring only.
- `session/session-events.ts`: event types and normalization.
- `session/session-prompting.ts`: prompt/follow-up/steering.
- `session/session-system-prompt.ts`: rebuild signatures and prompt refresh.
- `session/session-compaction.ts`: manual/auto compaction and handoff.
- `session/session-retry.ts`: retry/fallback logic.
- `session/session-permissions.ts`: ACP and runtime permission integration.
- `session/session-todo-reminders.ts`: todo reminders and auto-clear.
- `session/session-tool-registry.ts`: tool registry refresh/activation.
- `session/session-mcp-discovery.ts`: MCP/discoverable tool selection.
- `session/session-eval-lifecycle.ts`: eval cleanup and tracking.
- `session/session-subagent-events.ts`: task/IRC/subagent progress aggregation.

Refactor `KajiAgentRuntime/src/sdk.ts` into:

- `sdk/create-agent-session.ts`.
- `sdk/session-context-builder.ts`.
- `sdk/runtime-tool-builder.ts`.
- `sdk/runtime-prompt-builder.ts`.
- `sdk/runtime-mcp-setup.ts`.
- `sdk/runtime-extension-setup.ts`.
- `sdk/runtime-lsp-setup.ts`.

Refactor `KajiAgentRuntime/src/tools/index.ts` into:

- `tools/catalog.ts`.
- `tools/hidden-catalog.ts`.
- `tools/tool-factory.ts`.
- `tools/tool-gates.ts`.
- `tools/tool-resolver.ts`.
- `tools/discovery-policy.ts`.

This directly aligns with the repository's own rule that files should do one thing and large files should be split.

### Phase 2 — Add Declarative Runtime Profiles

Goal: make Kaji's harness behavior visible and configurable.

Add `KajiAgentRuntime/src/runtime/profile.ts`:

```ts
export interface RuntimeProfile {
  id: string;
  mode: "rpc" | "tui" | "acp" | "subagent";
  toolPatterns: string[];
  hiddenToolPatterns: string[];
  maxRequestsPerTurn: number;
  maxToolFailuresPerTurn: number;
  toolTimeouts: Record<string, number>;
  retryPolicy: RetryPolicy;
  compactionPolicy: CompactionPolicy;
  permissionPolicy: PermissionPolicy;
  promptProfile: PromptProfile;
  subagentPolicy: SubagentPolicy;
}
```

Create built-in profiles:

- `kaji-rpc-build`.
- `kaji-rpc-plan`.
- `kaji-rpc-explore`.
- `kaji-rpc-review`.
- `kaji-subagent-default`.
- `kaji-subagent-explore-lite`.

Move `applyRpcDefaultSettingOverrides()` to populate the `kaji-rpc-build` profile rather than individually overriding many unrelated settings.

### Phase 3 — Implement Forge-Style Tool Resolver

Goal: make tools predictable and easy to reason about.

Add resolver semantics:

- Exact tool name.
- Glob patterns: `fs_*`, `kaji_*`, `mcp/github_*`.
- Deprecated aliases: `search -> find/search`, old tool names, host aliases.
- Deduplication.
- Explicit order.
- Per-profile hidden vs visible sets.
- Provider/model transform hook.

Use resolver for:

- Built-in tools.
- Hidden tools.
- MCP tools.
- Extension tools.
- Swift host tools.
- Discovered BM25 tools.

### Phase 4 — Centralize Permissions

Goal: one permission service for all tools and hosts.

Add `KajiAgentRuntime/src/permissions/permission-service.ts` with:

- Rulesets: default, profile, session, tool, host, user.
- Wildcard matching for permission key and pattern.
- Permission names: `read`, `edit`, `write`, `delete`, `move`, `bash`, `mcp:*`, `kaji:*`, `lsp`, `browser`, `web`, `task`, `skill`.
- Pending request store.
- Replies: allow once, allow session, allow always, deny once, deny session, deny always, corrected/rejected feedback.
- Event output: `permission_request`, `permission_response`, `permission_denied`.
- Swift RPC bridge adapter.
- ACP bridge adapter.
- Extension tool adapter.

Then route these through it:

- Bash/edit/write/delete/move/read-secret approvals.
- MCP tool approvals.
- Swift host tools.
- Browser tools.
- Task/subagent permissions.
- Plan-mode enforcement.

### Phase 5 — Add Native Kaji Code Graph Tools

Goal: make Kaji's own context engine a first-class runtime advantage.

Add Swift or runtime host tools:

1. `kaji_code_graph_report`
   - Returns graph report summary and relevant communities.
   - Reads `graphify-out/GRAPH_REPORT.md` for the active project.
2. `kaji_code_graph_search`
   - Search nodes/symbols/files by text/query.
   - Returns exact node IDs, labels, files, and community IDs.
3. `kaji_code_graph_neighbors`
   - Given node/file/symbol, return incoming/outgoing dependencies and related source files.
4. `kaji_code_graph_path`
   - Find relationship path between two symbols/files.
5. `kaji_code_graph_hotspots`
   - Return high-degree hubs and likely architecture entry points.

Prompt rule:

- Use code graph before broad repository exploration when a graph is available.
- Use `kaji_fff_search` for exact text and `kaji_code_graph_search` for architecture/dependency navigation.
- Do not dump huge graph data; retrieve targeted neighborhoods.

This is the clearest "Kaji-only" improvement. Forge advertises codebase understanding; Kaji already has a graph extension and should wire it into the native agent.

### Phase 6 — Strengthen Prompt Composition

Goal: keep Kaji's strong prompt but reduce bloat and improve testability.

Split prompt modules:

- `prompts/system/core.md`.
- `prompts/system/coding-workflow.md`.
- `prompts/system/tool-policy.md`.
- `prompts/system/worktree-safety.md`.
- `prompts/system/planning.md`.
- `prompts/system/subagents.md`.
- `prompts/system/verification.md`.
- `prompts/system/kaji-native.md`.
- `prompts/system/model/openai.md`.
- `prompts/system/model/anthropic.md`.
- `prompts/system/model/gemini.md`.

Add a typed prompt context similar to Forge's `SystemContext`:

```ts
export interface KajiPromptContext {
  environment: RuntimeEnvironment;
  profile: RuntimeProfileSummary;
  tools: PromptToolSummary[];
  visibleToolNames: Record<string, string>;
  hiddenCapabilities: HiddenCapabilitySummary[];
  workspace: WorkspaceSummary;
  git: GitSummary;
  skills: SkillSummary[];
  rules: RuleSummary[];
  mcp: MCPPromptSummary;
  host: KajiHostSummary;
  codeGraph?: CodeGraphSummary;
}
```

### Phase 7 — Add Lite Explore/Research Subagent

Goal: keep Kaji's powerful `task` system but add OpenCode-like simplicity.

Add a `explore-lite` subagent profile:

- Tools: `read`, `find`, `search`, `ast_grep`, `lsp`, `kaji_fff_find`, `kaji_fff_search`, `kaji_code_graph_*`, optional `web_search`.
- No `bash` by default, or read-only bash only.
- No edits.
- No todo writes.
- Final output only; no complex schema unless requested.
- Very cheap model override possible.

Use it in plan mode and early investigation prompts.

### Phase 8 — Improve Native Host Tools

Add host tools beyond FFF:

- `kaji_get_open_tabs`.
- `kaji_get_editor_selection`.
- `kaji_get_visible_file_context`.
- `kaji_get_terminal_panes`.
- `kaji_get_worktree_status`.
- `kaji_show_diff`.
- `kaji_open_diff`.
- `kaji_focus_file_range`.
- `kaji_report_diagnostics`.
- `kaji_code_graph_*` tools from Phase 5.

These should be exposed via the same tool resolver and permission service, not manually special-cased in unrelated UI code.

### Phase 9 — Edit Safety and Undo

Goal: make editing behavior auditable across all edit-capable tools.

Add an edit safety contract:

- Every edit-capable tool declares whether it requires prior read/snapshot.
- Every edit-capable tool produces a diff metadata object.
- Every edit-capable tool records before/after snapshots.
- Every edit-capable tool uses the central permission service.
- Every edit-capable tool triggers diagnostics where possible.
- Every edit-capable tool supports undo or checkpoint integration.

Add first-class `undo` tool:

- Undo last edit by this session.
- Undo by edit ID.
- Show pending undo diff before applying.
- Integrate with `checkpoint`/`rewind`.

### Phase 10 — Todo Read and Todo Verification

Goal: adopt Forge's `verify_todos` idea and make todo state inspectable.

Add:

- `todo_read` tool.
- `todo_verify` internal step or policy.
- Tests that final response is blocked/warned if todos remain incomplete after a supposedly completed coding task.
- Native Swift UI indicator for incomplete todo phases.

Kaji already has eager todo and reminders, so this is a small incremental improvement.

### Phase 11 — Model-Specific Tool Profiles

Goal: improve reliability for different models.

Borrow OpenCode's model-family tool switching idea:

- Some models get `apply_patch`-style tools.
- Some models get exact `edit` only.
- Weaker/local models get compound tools with fewer decisions.
- Stronger models get granular tools.
- Non-tool models get Forge-style tool-use text prompt fallback if needed.

Add `ModelHarnessProfile`:

```ts
export interface ModelHarnessProfile {
  modelPattern: string;
  preferredEditTool: "edit" | "patch" | "ast_edit" | "compound_edit";
  maxParallelToolCalls?: number;
  toolDescriptionBudget?: number;
  forceToolChoiceSupported: boolean;
  reasoningStyle: "none" | "low" | "medium" | "high";
}
```

### Phase 12 — Observability and Debugging

Goal: make Kaji runtime behavior explainable.

Add debug commands/tools:

- `runtime_profile_dump`.
- `tool_catalog_dump`.
- `prompt_preview`.
- `permission_rules_dump`.
- `subagent_tree_dump`.

Add telemetry counters:

- Tool failures per turn.
- Tool retries.
- Permission asks/denies.
- Prompt rebuild count.
- System prompt token size.
- MCP activated tools.
- Code graph tool usage.
- Subagent token/cost totals.

## Priority Order

If doing this in practical implementation order:

1. **Snapshot tests first** for prompts, tools, and RPC events.
2. **Split `agent-session.ts`, `sdk.ts`, and `tools/index.ts`** without behavior changes.
3. **Introduce `RuntimeProfile`** and migrate RPC defaults into it.
4. **Introduce `ToolResolver`** and keep current tool output unchanged.
5. **Introduce central `PermissionService`** behind existing ACP/extension/host approval adapters.
6. **Add Kaji code graph host tools**.
7. **Add `explore-lite` subagent profile**.
8. **Add richer native host tools**.
9. **Add todo read/verify and first-class undo**.
10. **Add model-specific harness profiles**.

## Concrete First PR

Recommended first PR scope:

- No feature changes.
- Add `KajiAgentRuntime/docs/runtime-map.md`.
- Add snapshot tests for:
  - default RPC prompt.
  - default RPC tool list.
  - plan mode prompt/tool list.
  - task tool schema.
- Add a `RuntimeProfile` type and a read-only `kajiRpcRuntimeProfile()` factory that mirrors today's settings without changing behavior.

Why this first:

- It gives us a verified baseline.
- It makes later refactors safe.
- It prevents adding more behavior to already huge files.
- It creates a place to compare Kaji against Forge/OpenCode in code, not just docs.

## Sources To Keep Rechecking

- ForgeCode: https://forgecode.dev/ and https://github.com/tailcallhq/forgecode
- OpenCode: https://github.com/anomalyco/opencode and https://opencode.ai/docs/
- OpenCode agents docs: https://opencode.ai/docs/agents/
- OpenCode tools docs: https://opencode.ai/docs/tools/
- Kaji architecture: `docs/architecture.md`
- Kaji code graph: `graphify-out/GRAPH_REPORT.md` and `graphify-out/kaji-graph.json`

## Implementation Status — 2026-06-06

Completed runtime harness improvements:

- Phase 0 baseline doc and fixtures: `KajiAgentRuntime/docs/runtime-map.md`, plus prompt/tool/RPC host frame harness fixtures in `test/runtime-harness-snapshot.test.ts`.
- Phase 2 runtime profiles: declarative Kaji RPC, plan, explore, review, default subagent, and explore-lite profiles.
- Phase 3 tool resolver: exact names, glob patterns, deprecated aliases, dedupe, unknown tracking, and `createTools` integration.
- Phase 4 permission service: ACP destructive-tool flow and runtime tool approval flow now route through `PermissionService`; durable ACP decisions are persisted as session custom entries, permission snapshots expose session/persistent durations, and browser/host/MCP/web/runtime permission telemetry is available by key and category.
- Phase 5 code graph host tools: native Swift host catalog exposes report, search, neighbors, path, and hotspots.
- Phase 8 workspace host tools: native tools for open tabs, editor selection, visible file context, terminal panes, worktree status, diff show/open, file-range focus, diagnostics, and code graph context.
- Phase 10 todo inspection and native visibility: first-class `todo_read` and `todo_verify` tools with failing verification when incomplete todos remain, plus a native Kaji Agent header indicator for open todos.
- Phase 11 model harness profiles: model-family resolver for preferred edit style, parallelism, tool description budget, tool-choice support, and reasoning style.
- Phase 12 debug tools and telemetry: `runtime_profile_dump`, `runtime_telemetry_dump`, `tool_catalog_dump`, `prompt_preview`, `permission_rules_dump`, and `subagent_tree_dump`; telemetry now tracks tool failures, retries, compactions, prompt rebuilds, discovery activation, code graph usage, permission asks/denies by key/category, and session usage.
- Phase 6 prompt composition: typed `KajiPromptContext` now drives Kaji-native, code graph, workspace, todo verification, and runtime-debug prompt sections.
- Phase 9 edit safety: local `edit`, `write`, applied `ast_edit`, writable internal URLs, and client-bridge writes now record target-kind metadata; first-class `undo` previews/restores safe records and requests diagnostics after local restores when LSP diagnostics-on-write is enabled.
- Phase 1 monolith split: `ToolSession` and context-file types live in `tools/tool-session.ts`; built-in/hidden tool catalogs live in `tools/tool-catalog.ts`; edit safety targets live in `tools/edit-safety-targets.ts`; session metadata, no-op UI context, IRC reply dedupe, handoff helpers, and tool-call batch caps are split out of `agent-session.ts`; custom-tool extension adaptation is split out of `sdk.ts`.

Current verification evidence:

- `cd KajiAgentRuntime && bun run check:types`
- `cd KajiAgentRuntime && bun run build`
- `cd KajiAgentRuntime && bun test test/runtime-harness-snapshot.test.ts`
- `cd KajiAgentRuntime && bunx biome lint .`
- `PATH="$(dirname $(which bun)):$PATH" scripts/build-kaji-agent-runtime.sh`
- `git diff --check`
- `swift test --filter KajiAgentHostToolCatalogTests`
- `swift test --filter KajiAgentTodoIndicatorTests`
- `scripts/checks.sh --fix`
- Targeted runtime tests:
  - `src/tools/runtime-debug.test.ts`
  - `src/permissions/permission-service.test.ts`
  - `src/tools/edit-safety.test.ts`
  - `test/system-prompt-templates.test.ts`
  - `src/runtime/profile.test.ts`
  - `src/tools/todo-verify.test.ts`
  - `src/tools/todo-read.test.ts`
  - `src/tools/tool-resolver.test.ts`
  - `test/tools/approval-mode.test.ts`
  - `test/tools/approval.test.ts`

Known remaining work before calling the full plan complete:

- None from the implementation plan tracked in this document. Continue future hardening with broader end-to-end app validation and incremental decomposition of very large legacy files as separate maintenance work.
