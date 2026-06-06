# KajiAgentRuntime CodeGraph Preflight and Subagent Failure Plan

Date: 2026-06-06
Scope: KajiAgentRuntime harness plus the Kaji host-tool/UI surfaces that feed it. This does not cover the full Kaji app outside coding-agent runtime integration.

## User-visible problems

1. CodeGraph missing state is shown as a failed `kaji_code_graph_report` call.
   - The current UX tells the agent/user that `kaji_code_graph_report` failed even when the correct state is simply `not built yet`.
   - The agent has no cheap non-error yes/no tool to check whether the graph and report exist before calling report/search/neighbors/path/hotspots.

2. Subagents always fail before doing work.
   - The screenshot shows `failed`, `Current tool -`, `Tokens 0`, and short runtime.
   - Persisted runtime sessions confirm the failure happens during subagent startup before any model turn or tool execution.
   - The subagent detail modal does not surface the captured `stderr`/`error`, so the UI hides the real failure reason.

## Evidence from code

### CodeGraph host tools

Current definitions are in `Kaji/Services/KajiAgentCodeGraphHostToolDefinitions.swift`.

The tool list is:

- `kaji_code_graph_report`
- `kaji_code_graph_search`
- `kaji_code_graph_neighbors`
- `kaji_code_graph_path`
- `kaji_code_graph_hotspots`

There is no `status`, `exists`, or `preflight` tool.

Execution is dispatched in `Kaji/Services/KajiAgentHostToolRegistry.swift` and each CodeGraph read tool is implemented in `Kaji/Services/KajiAgentCodeGraphHostTools.swift`.

Current behavior:

- `report` resolves the active Kaji workspace, calculates `GRAPH_REPORT.md` and `kaji-graph.json`, then returns `KajiAgentCodeGraphMissingResult.report(...)` when the report does not exist.
- `search`, `neighbors`, `path`, and `hotspots` return `KajiAgentCodeGraphMissingResult.graph(...)` when `kaji-graph.json` does not exist.
- Missing graph/report is semantically a workspace state, not a tool failure.

Prompt guidance currently exists in `KajiAgentRuntime/src/prompts/system/system-prompt.md` and bundled output under `Kaji/Resources/KajiAgentRuntime/kaji-agent-runtime.mjs`.

The prompt says to use `kaji_code_graph_search` or `kaji_code_graph_report` before broad repository exploration. It does not say to check availability first, because that tool does not exist yet.

### Subagent startup failure

Persisted session evidence under `~/Library/Application Support/Kaji/AgentRuntime/sessions/` shows every failed subagent returning:

```text
ReferenceError: MAX_MCP_INSTRUCTIONS_LENGTH is not defined
    at <anonymous> (/Users/dishants/projects/muxy/KajiAgentRuntime/src/sdk.ts:1437:32)
    at async createAgentSession (/Users/dishants/projects/muxy/KajiAgentRuntime/src/sdk.ts:1591:41)
    at async <anonymous> (/Users/dishants/projects/muxy/KajiAgentRuntime/src/task/executor.ts:1105:26)
    at async <anonymous> (/Users/dishants/projects/muxy/KajiAgentRuntime/src/task/executor.ts:1207:30)
    at async runSubprocess (/Users/dishants/projects/muxy/KajiAgentRuntime/src/task/executor.ts:1504:3)
```

`KajiAgentRuntime/src/sdk.ts` references `MAX_MCP_INSTRUCTIONS_LENGTH` at two locations:

- In `rebuildSystemPrompt(...)`, when appending MCP server instructions into the system prompt.
- In `getMcpServerInstructions`, when passing truncated MCP server instructions to the `AgentSession`.

There is no matching definition or import in `sdk.ts`, so subagent session creation crashes when parent MCP instructions are present.

This matches the screenshot:

- `tokens = 0`, because the model loop never starts.
- `current tool = -`, because no tool call is reached.
- short duration, because it fails during `createAgentSession`.

### Subagent UI evidence gap

The Swift UI model is in `Kaji/Models/KajiAgentSubagentModels.swift`.

`KajiAgentSubagentResult` parses:

- `output`
- `error`
- `outputPath`

But `KajiAgentSubagentProgress.init(result:)` only converts `result.output` into `recentOutput`. If `output` is empty and `stderr`/`error` exists, the visible fallback progress has no error text.

`Kaji/Views/KajiAgent/KajiAgentSubagentDetailView.swift` displays assignment, status, current tool, tokens, duration, transcript, and recent output. It has no failure/error section.

So even when the runtime returns a precise startup failure in `details.results[].error`, the modal can still show an empty failed subagent.

## Root causes

### CodeGraph

The harness treats unavailable CodeGraph artifacts as errors from the first CodeGraph read tool. There is no first-class availability contract for the agent.

The correct model should be:

1. Check active context.
2. Check CodeGraph status without failing.
3. If ready, call report/search/path/neighbors/hotspots.
4. If missing, fall back to repo tools and tell the user the CodeGraph needs to be built from the footer.

### Subagents

The immediate hard failure is a missing runtime constant in `sdk.ts` after the harness refactor/extraction work. The same class of issue already appeared with earlier missing symbols like `registerSshCleanup` and `resolveToolCallBatchCapForModel`.

The deeper issue is that the subagent startup path is not guarded by enough tests around parent-inherited MCP/server-instruction state. A top-level session can still appear healthy while in-process subagents crash during child `createAgentSession`.

The UI issue is separate: failed subagent results carry useful error fields, but the visible detail model drops them.

## Implementation plan

### Phase 1: Add a non-error CodeGraph status tool

Add a new host tool named `kaji_code_graph_status`.

Files:

- `Kaji/Services/KajiAgentCodeGraphHostToolDefinitions.swift`
- `Kaji/Services/KajiAgentCodeGraphHostTools.swift`
- `Kaji/Services/KajiAgentHostToolRegistry.swift`
- `Tests/KajiTests/Services/KajiAgentHostToolCatalogTests.swift`
- New or extended CodeGraph status tests under `Tests/KajiTests/Services/`

Behavior:

- Return `isError = false` for every normal workspace state.
- Return structured details:
  - `hasActiveProject`
  - `hasReport`
  - `hasGraph`
  - `ready`
  - `reportPath`
  - `graphPath`
  - `message`
- If no active Kaji project exists, return non-error status with `hasActiveProject = false` and `ready = false`.
- Keep real IO/parsing failures in read tools as errors. Missing artifacts should be status, not a red failure.

Expected text output examples:

```text
CodeGraph ready: yes
Report: /.../GRAPH_REPORT.md
Graph: /.../kaji-graph.json
```

```text
CodeGraph ready: no
No KajiCodeGraph report or graph exists for the active worktree. Build it from the Code Graph footer button first.
```

Acceptance:

- Calling `kaji_code_graph_status` on a worktree with no graph returns `isError == false`.
- Calling `kaji_code_graph_status` on a worktree with graph/report returns `ready == true`.
- Existing read tools can still return user-facing missing-result errors if called directly, but the recommended path avoids them.

### Phase 2: Update prompt/tool guidance to preflight CodeGraph

Files:

- `KajiAgentRuntime/src/prompts/system/system-prompt.md`
- `Kaji/Services/CodingAgentShimScript.swift`
- Any runtime prompt snapshot tests that cover CodeGraph prompt text.
- Rebuilt runtime bundle: `Kaji/Resources/KajiAgentRuntime/kaji-agent-runtime.mjs`

Prompt policy:

- For architecture/dependency/navigation questions, call `kaji_code_graph_status` first.
- If status says ready, prefer `kaji_code_graph_report`/`search`/`neighbors`/`path`/`hotspots` before broad repo exploration.
- If status says missing, do not retry CodeGraph tools in a loop. Use normal repo tools and mention that the graph is not built.

Acceptance:

- Prompt snapshots include the new preflight rule.
- Tool metadata lists `kaji_code_graph_status` before the heavier graph tools.
- Agents have an obvious safe path that avoids red missing-graph tool calls.

### Phase 3: Fix MCP instruction truncation in the runtime

Files:

- `KajiAgentRuntime/src/sdk.ts`
- New small file if useful: `KajiAgentRuntime/src/mcp-instructions.ts`
- New or extended tests under `KajiAgentRuntime/test/`

Implementation options:

1. Minimal root fix: define/import `MAX_MCP_INSTRUCTIONS_LENGTH` in `sdk.ts`.
2. Cleaner root fix: extract formatting into a focused `mcp-instructions.ts` module and import it from `sdk.ts`.

Preferred implementation:

- Create a focused module with:
  - `MAX_MCP_INSTRUCTIONS_LENGTH`
  - `truncateMcpInstructions(text: string)`
  - `formatMcpServerInstructionBlocks(serverInstructions: Map<string, string>, existingPrompt?: string)`
  - `truncateMcpServerInstructionMap(serverInstructions?: Map<string, string>)`
- Replace both ad-hoc `MAX_MCP_INSTRUCTIONS_LENGTH` usages in `sdk.ts` with these functions.
- Keep file sizes small and avoid duplicating truncation behavior.

Tests:

- Unit test truncation length and `[truncated]` marker behavior.
- Unit test that `createAgentSession` with a parent-style MCP manager/server-instructions path does not throw before the model loop starts.
- Regression test that subagent `runSubprocess` can construct a child session when parent MCP instructions exist.

Acceptance:

- No runtime reference to an undefined `MAX_MCP_INSTRUCTIONS_LENGTH` remains.
- Subagent startup no longer fails with `tokens 0` due to this ReferenceError.

### Phase 4: Make subagent failures visible in the UI

Files:

- `Kaji/Models/KajiAgentSubagentModels.swift`
- `Kaji/Views/KajiAgent/KajiAgentSubagentDetailView.swift`
- Tests under `Tests/KajiTests/Models/`

Changes:

- Add an optional failure text field to `KajiAgentSubagentProgress`, derived from:
  - progress JSON error field if present
  - result error
  - result stderr if added to the Swift model
- Parse `stderr` in `KajiAgentSubagentResult` because runtime details include it.
- In `KajiAgentSubagentProgress.init(result:)`, preserve the best available failure text even when output is empty.
- In `KajiAgentSubagentDetailView`, show a `Failure` section above recent output when the agent failed and failure text exists.
- Show `outputPath` or transcript path when available.

Acceptance:

- A zero-token failed subagent modal shows the real error stack/message.
- The list can stay compact, but the detail view must never hide startup failure reasons.

### Phase 5: Runtime subagent startup hardening

Files:

- `KajiAgentRuntime/src/task/executor.ts`
- Related task/subagent tests.

Changes:

- On `createAgentSession` failure, ensure final progress includes failure text before returning.
- Ensure final `SingleResult` includes `error`, `stderr`, `durationMs`, `tokens`, `resolvedModel`, `outputPath`, and `aborted` consistently.
- Add a regression test for startup failure propagation so the UI always receives diagnostic text.

Acceptance:

- If future child-session startup fails, the parent task result and Swift detail modal both show why.
- Failed subagents are actionable instead of appearing as blank `failed 0 tokens` rows.

## Validation loop

Run the loop until clean:

1. Runtime type/test/lint/build

```bash
cd KajiAgentRuntime
bun run check:types
bun test test/runtime-harness-snapshot.test.ts
bun test test/sdk-session-isolation.test.ts
bun test test/tools/approval-mode.test.ts
bun test test/mcp-instructions.test.ts
bunx biome lint .
bun run build
```

2. Rebuild bundled runtime for Kaji

```bash
cd ..
scripts/build-kaji-agent-runtime.sh
```

3. Swift targeted tests

```bash
swift test --filter KajiAgentHostToolCatalogTests --filter KajiAgentCodeGraphMissingResultTests --filter KajiAgentSubagentInlineLayoutTests
swift test --filter KajiAgentSubagentModelsTests --filter KajiAgentCodeGraphStatusTests
```

4. Project checks

```bash
scripts/checks.sh --fix
git diff --check
```

5. Manual verification in Kaji

- Active worktree without built CodeGraph:
  - Ask an architecture question.
  - Confirm `kaji_code_graph_status` returns `ready: false` with no red error.
  - Confirm the agent falls back to normal repo tools and mentions the graph is missing once.
- Active worktree with built CodeGraph:
  - Confirm `kaji_code_graph_status` returns `ready: true`.
  - Confirm agent uses report/search normally.
- Subagent task:
  - Run a task that launches multiple `explore` subagents.
  - Confirm subagents produce model tokens and tool activity.
  - If any subagent fails for a real provider/tool reason, confirm the detail modal shows the exact failure text.

## Deployment-ready acceptance criteria

- CodeGraph missing artifacts no longer create first-step red error UX when the agent follows prompt guidance.
- `kaji_code_graph_status` is available, documented in tool metadata, tested, and returns non-error status for missing artifacts.
- Subagents no longer crash with `ReferenceError: MAX_MCP_INSTRUCTIONS_LENGTH is not defined`.
- Subagent startup with parent MCP instructions is covered by regression tests.
- Subagent failure diagnostics are preserved from runtime result to Swift model to detail modal.
- Runtime bundle is rebuilt and Swift build/checks pass.
- No unrelated dirty work is staged or modified beyond the targeted implementation files.
