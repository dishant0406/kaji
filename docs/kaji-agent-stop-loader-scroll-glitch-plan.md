# Kaji Agent Stop Loader and Subagent Scroll Glitch Plan

## Problem

Two regressions remain in the Kaji Agent SwiftUI surface:

1. Pressing the composer stop button stops the agent process state, but the floating task/todo button can keep showing the working spinner/animated loader.
2. While task subagents are streaming progress, scrolling upward is still glitchy and can snap back toward the bottom.

## Source-grounded findings

### Stop button path

- The composer stop action calls `KajiAgentHome.stop()` (`Kaji/Views/KajiAgent/KajiAgentHome.swift:366-369`), which delegates to `store.stop()`.
- `KajiAgentStore.stop()` flushes pending coalesced UI updates, sends the `abort` RPC, and sets `isRunning = false` (`Kaji/Services/KajiAgentStore.swift:118-122`). It does not update `todoPhases`, mutate task tool details embedded in `turns`, or mark active tool messages complete/aborted.
- Runtime RPC mode handles `abort` by awaiting `session.abort()` and returning a success response (`KajiAgentRuntime/src/modes/rpc/rpc-mode.ts:542-545`).
- `AgentSession.abort()` aborts retry/compaction/handoff/bash/eval, aborts the agent, waits for idle, and calls goal abort handling (`KajiAgentRuntime/src/session/agent-session.ts:4464-4488`). It does not guarantee a Swift-visible `tool_execution_end` or final task progress payload for every active task tool.
- Swift only updates task tool details through `KajiAgentToolTimelineApplier.updateTaskDetails(...)` when `tool_execution_update` or `tool_execution_end` carries task details (`Kaji/Services/KajiAgentToolTimelineApplier.swift:29-63,75-84`). If abort does not produce a final task tool event, existing `message.taskDetails` stays in the last running state.
- Todo phases are only replaced from runtime state snapshots (`Kaji/Services/KajiAgentStore.swift:716-724`), transcript restore (`Kaji/Services/KajiAgentStore.swift:730-737`), or `todo_write` tool effects (`Kaji/Services/KajiAgentToolTodoEffect.swift`). `applyState` preserves old todos when `snapshot.todoPhases == nil` (`Kaji/Services/KajiAgentStore.swift:721`).
- `KajiAgentFloatingTaskState.isWorking` is true if any todo is `in_progress`, any subagent status is `running`/`pending`/`in_progress`, any task async state is running, or `isAgentRunning && hasVisibleWork` (`Kaji/Models/KajiAgentFloatingTaskState.swift:24-26,67-99,119-126`). After `stop()`, `isAgentRunning` becomes false, but stale todo/subagent clauses can remain true forever.
- `KajiAgentFloatingTaskButton` renders `KajiSpinner` and the animated activity border whenever `state.isWorking` is true (`Kaji/Views/KajiAgent/KajiAgentFloatingTaskButton.swift:14-16,31-34`).

### Scroll path during subagent updates

- `KajiAgentHome.timeline` calls `scrollCoordinator.scrollToTurn(id)` when `store.turns.last?.id` changes (`Kaji/Views/KajiAgent/KajiAgentHome.swift:242-245`) and calls `scrollCoordinator.handleTailChanged()` on every `store.tailVersion` change (`Kaji/Views/KajiAgent/KajiAgentHome.swift:246-249`).
- Task/subagent progress updates flow through `KajiAgentToolTimelineApplier.update(...)`, which bumps `tailVersion` before updating tool output/task details (`Kaji/Services/KajiAgentToolTimelineApplier.swift:29-39`). Todo effects can bump `tailVersion` again when phases change (`Kaji/Services/KajiAgentToolTodoEffect.swift`).
- `KajiAgentTimelineUpdateCoalescer` reduces raw event frequency, but tool updates still flush at the UI cadence, so active subagents can produce repeated `tailVersion` changes while the user is scrolling.
- `KajiAgentScrollCoordinator.handleTailChanged()` checks distance from bottom and either marks unseen/locked or schedules a non-animated bottom scroll (`Kaji/Services/KajiAgentScrollCoordinator.swift:42-55`).
- `scheduleScrollToBottom` uses the same `pendingScroll` task as `scheduleScrollToTurn` and executes after a 16 ms delay (`Kaji/Services/KajiAgentScrollCoordinator.swift:75-81`). A tail update can cancel a pending turn scroll, and a turn scroll can later reset lock state.
- `performScrollToTurn` scrolls unconditionally and clears `isLocked`/`hasUnseenTail` (`Kaji/Services/KajiAgentScrollCoordinator.swift:116-129`). It does not respect the user’s current scroll lock.
- `observe(_:)` ignores bounds changes for 0.18 s after programmatic scrolls (`Kaji/Services/KajiAgentScrollCoordinator.swift:70-72`). During that suppression window, user wheel input can be missed, then a delayed scheduled scroll can still run.
- The current scroll lock policy has a 4 px pinned threshold and 8 px away threshold (`Kaji/Services/KajiAgentScrollLockPolicy.swift`). This is directionally correct, but the coordinator still schedules/executes scroll work from multiple reactive hooks and clears lock state in `performScrollToTurn`.
- The timeline has two `.scrollTargetLayout()` sections, one for history and one for live tail (`Kaji/Views/KajiAgent/KajiAgentHome.swift:197-236`). Subagent list rows can change height and ordering while progress changes (`Kaji/Views/KajiAgent/KajiAgentSubagentListView.swift`, `Kaji/Models/KajiAgentSubagentInlineLayout.swift`), increasing content-height churn while scroll updates are being scheduled.

## Root causes

### Loader stays active after stop

The UI derives working state from persisted task/todo progress, but the stop path only changes `isRunning`. It does not reconcile in-flight UI progress to an aborted/idle terminal state. Because abort is asynchronous and not guaranteed to emit final task/todo updates, the floating button can keep seeing stale `in_progress` todos and `running` subagents.

### Scroll snaps back during subagent updates

The scroll policy handles distance thresholds, but the coordinator still has three snap-back mechanisms:

1. `scrollToTurn` ignores `isLocked` and clears lock state.
2. Tail-update scroll and turn-scroll share one cancellation slot, so frequent subagent `tailVersion` updates can race/cancel/replace intended scroll actions.
3. Programmatic-scroll debounce suppresses user bounds observation, so a quick user scroll during streaming can be missed before the scheduled bottom scroll fires.

## Implementation plan

### Phase 1: Make stop produce a terminal UI state

Add a local Swift-side abort reconciliation path in `KajiAgentStore.stop()` immediately after flushing pending updates and before/after sending `abort`.

Concrete changes:

1. Add a timeline helper, e.g. `KajiAgentTimeline.markActiveWorkAborted(...)`, that walks active/incomplete tool messages and task details in `turns`.
2. For incomplete tool messages:
   - set `isComplete = true`;
   - set `isError = false` unless an actual runtime error is known;
   - preserve existing detail/preview output;
   - append or replace a neutral title/detail summary only if the tool row would otherwise look still running.
3. For `KajiAgentTaskToolDetails` with live `progress` entries:
   - convert statuses `running`, `pending`, and `in_progress` to `aborted` or `cancelled`;
   - preserve assignment/task/recent output/token metadata;
   - preserve completed/failed entries unchanged.
4. For todo phases:
   - either convert `in_progress` tasks to `abandoned`/`cancelled`, or add a separate stopped/run-state overlay so `KajiAgentFloatingTaskState.isWorking` no longer treats old in-progress todos as active when `store.isRunning == false` after a user stop.
   - Prefer explicit store-level reconciliation over only weakening `isWorking`; otherwise a future active session could inherit stale in-progress todos.
5. Bump `tailVersion` once if any visible work state was reconciled so the floating button and visible rows update immediately.
6. Keep sending `abort` to runtime; if final runtime events arrive later, normal appliers can replace the local aborted state with authoritative final state.

Acceptance criteria:

- Pressing Stop immediately removes the spinner and animated activity border from the floating task button.
- Stopped subagents no longer display as running/pending/in-progress in the floating popover.
- Existing completed and failed subagent results remain unchanged.
- Existing todo text remains visible; only active status is made non-working.
- Later runtime final events can still update the timeline without duplicating rows or corrupting IDs.

Tests:

- Unit test `markActiveWorkAborted` with a running task tool: statuses become aborted/cancelled, message identity remains stable, and `tailVersion` increments once.
- Unit test completed/failed subagents are preserved.
- Unit test floating state after stop reconciliation: `hasVisibleWork == true`, `isWorking == false`.
- Unit test active todos no longer produce a loader after stop reconciliation.

### Phase 2: Separate user-locked scroll state from programmatic scrolling

Refactor `KajiAgentScrollCoordinator` so user scroll intent cannot be cleared by non-forced programmatic paths.

Concrete changes:

1. Split pending operations:
   - `pendingBottomScroll: Task<Void, Never>?`
   - `pendingTurnScroll: Task<Void, Never>?`
   This prevents frequent `tailVersion` updates from cancelling a pending new-turn scroll and prevents turn-scroll scheduling from overwriting tail-scroll state.
2. Make `scrollToTurn` respect lock state:
   - if `isLocked == true`, do not perform turn scroll; set `hasUnseenTail = true` instead;
   - allow force only for explicit user actions if needed in the future.
3. Make `performScrollToTurn` not clear lock state unless the operation was explicitly allowed/forced.
4. Make non-forced `performScrollToBottom` re-check both `isLocked` and `distanceFromBottom <= pinnedThreshold` immediately before setting bounds origin. If not pinned, set `isLocked = true`, `hasUnseenTail = true` and return.
5. Remove or reduce the 0.18 s observation suppression for non-animated streaming scrolls. Streaming bottom follow is already non-animated; suppressing user observation for 180 ms after every streaming update is too long while subagents update many times per second.
6. Track a lightweight manual-scroll signal if necessary:
   - store last observed `bounds.origin.y`;
   - if origin moves upward while not in a forced programmatic scroll, immediately lock regardless of distance threshold.

Acceptance criteria:

- While subagents stream, any upward scroll gesture prevents further auto-follow until the user clicks Jump to latest or scrolls fully to bottom.
- New turn insertion does not snap a locked user back to bottom.
- Tail updates no longer cancel turn-scroll bookkeeping in a way that clears lock state.
- Jump to latest remains immediate and clears lock/unseen state.
- At-bottom streaming still follows smoothly without visible drift.

Tests:

- Pure policy tests for manual upward movement: locks regardless of small distance.
- Coordinator-level testable helper for non-forced bottom scroll precondition: false when locked or away from bottom.
- Tests for `scrollToTurn` behavior when locked: sets unseen and does not clear lock.
- Existing scroll lock policy tests continue passing.

### Phase 3: Reduce subagent-driven scroll churn

After the coordinator correctness fix, reduce the amount of scroll work triggered by subagent-only updates.

Concrete changes:

1. Split `tailVersion` into semantic versions or add a lighter event flag:
   - content append/new row version: may auto-follow when pinned;
   - in-place task progress version: should update visible UI but should not schedule bottom scroll when user is interacting.
2. In `KajiAgentStore`, when `tool_execution_update` only changes `taskDetails`/preview inside an existing visible tool, mark a progress update rather than a new tail append.
3. In `KajiAgentHome`, call `scrollCoordinator.handleTailChanged()` only for append/growth events that need tail following, not every task detail/status refresh.
4. If semantic versioning is too large for this fix, add a short-term debounce in `KajiAgentScrollCoordinator.handleTailChanged()` that coalesces unseen-tail updates without scheduling repeated bottom scrolls while the user is near-but-not-pinned.

Acceptance criteria:

- Subagent progress updates still refresh rows/popover.
- Repeated subagent updates do not repeatedly schedule scroll work when no content was appended at the tail.
- Assistant text streaming at bottom still follows tail.

Tests:

- Store/applier test verifies task-detail-only updates do not advance an auto-scroll version if semantic versioning is implemented.
- UI coordinator test verifies repeated tail updates while locked only set unseen once and do not enqueue bottom scrolls.

### Phase 4: Verify with product scenarios

Manual scenarios:

1. Start a task with multiple subagents, scroll up while subagents are running, verify the viewport stays where the user placed it.
2. Click Jump to latest, verify follow resumes.
3. Start a task, wait for floating button spinner, press Stop, verify spinner/gradient border stop immediately.
4. Open the floating popover after Stop, verify subagents/todos are visible but not shown as actively running.
5. Let runtime deliver late final events after Stop, verify no duplicate or conflicting status rows.

Commands:

- Targeted Swift tests for new abort reconciliation and scroll coordinator/policy changes.
- `swift build`.
- `swift test`.
- `scripts/checks.sh --fix`; current environment has previously failed because `swiftformat` is missing, so report that exact prerequisite if unchanged.

## Recommended implementation order

1. Add abort reconciliation helper and tests.
2. Wire `KajiAgentStore.stop()` to reconcile local task/todo UI state immediately.
3. Refactor scroll coordinator pending tasks and lock-respecting turn scroll.
4. Add/adjust scroll policy tests for manual upward scroll and non-forced scroll preconditions.
5. If snapback persists under manual testing, split tail update signals so task progress updates do not schedule bottom scroll work.
6. Build/test/fix loop.
