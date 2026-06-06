# Kaji Agent Subagent Timeline Overlap Research And Fix Plan

## User-visible failure

A `task` tool with four failed subagents is rendering its inline `Subagents` list on top of the following assistant/thinking text. The same run also shows `kaji_code_graph_report` failing because the active worktree has no generated KajiCodeGraph report.

The CodeGraph error is valid data, but the transcript layout must remain stable for failed tools, long previews, and multi-subagent batches.

## Code paths inspected

- `Kaji/Views/KajiAgent/KajiAgentHome.swift`
  - Owns the transcript `ScrollView` and `LazyVStack`.
  - Renders every `KajiAgentTurnView` and forces the latest turn to at least the visible timeline height.
  - Auto-expands new tool groups from `store.tailVersion`.
- `Kaji/Views/KajiAgent/KajiAgentTurnView.swift`
  - Renders user message and response blocks in a vertical stack.
- `Kaji/Views/KajiAgent/KajiAgentToolGroupView.swift`
  - Renders an expanded group of adjacent tool calls.
  - Calls `KajiAgentMessageRow` for each tool.
- `Kaji/Views/KajiAgent/KajiAgentMessageRow.swift`
  - Renders tool header, tool output preview, and task details.
  - Tool output preview already has a bounded `ScrollView` with `maxHeight` 180 collapsed / 360 expanded.
  - Task details are appended below output with no independent height policy.
- `Kaji/Views/KajiAgent/KajiAgentTaskToolView.swift`
  - Renders the inline `Subagents` header and all `details.visibleAgents` in an unbounded `VStack`.
  - There is no max height, no inline item cap, no overflow row, no clipping, and no scroll boundary.
- `Kaji/Models/KajiAgentSubagentModels.swift`
  - Parses `progress[]`, `results[]`, async state, and exposes `visibleAgents`.
  - `visibleAgents` returns every progress item or every result item.
- `Kaji/Services/KajiAgentToolTimelineApplier.swift`
  - Adds `taskDetails` to the active tool from partial/final task tool result details.
- `Kaji/Services/KajiAgentCodeGraphHostTools.swift`
  - `kaji_code_graph_report` returns an error when `GRAPH_REPORT.md` is missing for the active worktree.
  - This is expected when the user has not built KajiCodeGraph for that worktree.

## Root cause hypothesis

The direct root cause is the unbounded inline subagent list in `KajiAgentTaskToolView`. Unlike normal tool output, the subagent list is not treated as a bounded transcript artifact. During streaming updates, a failed `kaji_code_graph_report` preview, followed by an expanded `task` tool with several subagent rows, creates a tall dynamic block inside a `LazyVStack`. The following assistant/thinking row can be laid out before the task view's height stabilizes, so the task rows visually collide with the next block.

This is not a CodeGraph data problem. The missing graph only creates the failure scenario quickly because it produces a failed tool preview plus a failed task batch. The timeline must handle that combination.

## What Kaji has today

- Bounded tool output previews.
- Full subagent details modal via `KajiAgentSubagentDetailView`.
- Parsed subagent progress/result data.
- Stable task details on partial and final tool updates.

## What is missing

- A transcript-specific inline policy for task/subagent batches.
- A max inline height for the subagent list.
- A compact overflow affordance such as `+ 3 more subagents`.
- A deterministic row height policy for subagent rows.
- Tests around subagent summary/overflow behavior.
- Optional structured missing-CodeGraph metadata so the UI/agent can present a clearer recovery action.

## Fix plan

### Phase 1: Make the task inline view bounded

Create a small layout policy model, for example `KajiAgentSubagentInlineLayout`, in `Kaji/Models/` or `Kaji/Services/`.

Responsibilities:

- Compute counts by status.
- Select inline agents deterministically.
- Prefer running/pending first, then failed/aborted, then completed.
- Expose `overflowCount`.
- Expose a concise summary string.
- Define constants for max inline rows and max inline height.

Recommended default:

- Show up to 3 or 4 rows inline.
- Add an overflow row when more agents exist.
- Keep the full list available through the existing subagent detail modal or a new summary modal.

### Phase 2: Split `KajiAgentTaskToolView`

Keep each file under 200 lines and one responsibility.

Suggested files:

- `Kaji/Views/KajiAgent/KajiAgentTaskToolView.swift`
  - Container only.
- `Kaji/Views/KajiAgent/KajiAgentSubagentListView.swift`
  - Header, bounded list, overflow row.
- `Kaji/Views/KajiAgent/KajiAgentSubagentRow.swift`
  - One row.
- `Kaji/Models/KajiAgentSubagentInlineLayout.swift`
  - Pure model/layout policy.

### Phase 3: Add a real list boundary

Update the inline list to use one of these stable approaches:

Preferred:

- Use a capped `VStack` with `inlineAgents` only.
- Add a `+ N more` row.
- Avoid nested vertical scrolling in the transcript unless the list is actively expanded.

Fallback if showing all visible subagents inline is required:

- Wrap the row stack in a vertical `ScrollView`.
- Apply `.frame(maxHeight: KajiAgentSubagentInlineLayout.maxHeight)`.
- Apply `.clipped()`.
- Keep a footer/overflow row outside the scroll area.

The preferred approach is better because nested scrolling inside a transcript is unpleasant and harder to test.

### Phase 4: Stabilize row measurement

For each subagent row:

- Add `.frame(maxWidth: .infinity, alignment: .leading)` to the row content.
- Keep title and detail line-limited.
- Give the row a predictable minimum height.
- Use `contentShape(RoundedRectangle(cornerRadius: 8))`.
- Prefer `onTapGesture` on the row over wrapping the whole row in `Button` if macOS button layout/focus rendering contributes to measurement instability.

### Phase 5: Improve CodeGraph missing-report UX

Keep the tool result as an error, but return structured details:

- `missingGraph: true`
- `kind: "codeGraphMissing"`
- `reportPath`
- `graphPath`

Then decide whether to add a small UI affordance later:

- `Build Code Graph` action if the active workspace context is still available.
- Or just improved text: `No CodeGraph for this worktree. Use the atom Code Graph button in the footer to build it.`

This is not needed to fix overlap, but it makes the screenshot scenario easier to recover from.

### Phase 6: Tests

Add pure Swift tests first:

- `Tests/KajiTests/Models/KajiAgentSubagentInlineLayoutTests.swift`
  - Counts running/completed/failed correctly.
  - Selects running/pending first.
  - Applies max inline row cap.
  - Computes overflow count.
  - Handles result-only task details.
- Extend `KajiAgentToolTimelineApplierTests` only if needed to verify that final result-only failed subagents still produce displayable task details.

Manual validation:

- Run a Kaji Agent task where `kaji_code_graph_report` fails and four subagents fail.
- Confirm no overlap with the following assistant/thinking message.
- Confirm the last-turn auto-scroll still follows streaming updates.
- Confirm clicking visible rows opens `KajiAgentSubagentDetailView`.
- Confirm overflow row tells the user how many agents are hidden inline.

### Phase 7: Validation commands

After implementation:

```bash
swift test --filter KajiAgentSubagentInlineLayoutTests
swift test --filter KajiAgentToolTimelineApplierTests
scripts/checks.sh --fix
```

If `scripts/checks.sh --fix` is too slow for iteration, run targeted tests first and only run the full script at the end.

## Acceptance criteria

- A task with 1, 4, 10, or 20 subagents never overlaps the next transcript row.
- Failed tools before the task do not affect subagent list layout.
- The transcript stays readable at the screenshot width.
- The full subagent data remains accessible.
- The changed Swift files stay small and single-purpose.
- New behavior is covered by model tests.
