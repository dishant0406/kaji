# Kaji Agent Floating Tasks and Scroll-Lock Plan

## Problem

Two UI issues remain in the Kaji Agent thread surface:

1. When the thread only slightly overflows the viewport, the user cannot reliably scroll upward while tasks/subagents are streaming because each tail update pulls the scroll view back to the bottom.
2. Todo/task state is rendered at the top of the UI and timeline. The requested UI is a bottom-right floating task button with an active/working visual state; clicking it opens a `KajiPopover` containing todos and active task/subagent progress.

## Source-grounded findings

### Scroll lock behavior

- `KajiAgentHome.timeline` calls `scrollCoordinator.handleTailChanged()` on every `store.tailVersion` change (`Kaji/Views/KajiAgent/KajiAgentHome.swift:264-267`).
- `KajiAgentScrollCoordinator.handleTailChanged()` auto-scrolls unless `isLocked == true` (`Kaji/Services/KajiAgentScrollCoordinator.swift:42-48`).
- `KajiAgentScrollCoordinator.observe(_:)` sets `isLocked = false` whenever `distanceFromBottom < 72` (`Kaji/Services/KajiAgentScrollCoordinator.swift:63-71`).
- For small overflow threads, a real user scroll-up can still leave `distanceFromBottom < 72`, so the coordinator classifies the user as “at bottom.” The next `tailVersion` update schedules `performScrollToBottom`, which resets the scroll position (`Kaji/Services/KajiAgentScrollCoordinator.swift:74-108`).
- `performScrollToBottom` always clears `isLocked` and `hasUnseenTail` after the scroll (`Kaji/Services/KajiAgentScrollCoordinator.swift:105-108`). That is correct for explicit jump-to-latest, but too aggressive for scheduled streaming scrolls unless the coordinator rechecks that the user is still pinned to the bottom.
- There is an unused duplicate scroll-state model, `KajiAgentTimelineScrollState`, with similar lock/unseen-tail state and a different debounce (`Kaji/Models/KajiAgentTimelineScrollState.swift`). It should be removed or folded into the coordinator during implementation to avoid two scroll state concepts.

### Current todo/task placement

- Header currently renders a todo pill through `KajiAgentTodoIndicator.active(phases:)` (`Kaji/Views/KajiAgent/KajiAgentHome.swift:83-86`).
- Empty state renders `KajiAgentTodoPanel(phases:)` inline (`Kaji/Views/KajiAgent/KajiAgentHome.swift:164-166`).
- Timeline renders `KajiAgentTodoPanel(phases:)` at the top of the scroll view (`Kaji/Views/KajiAgent/KajiAgentHome.swift:208-210`).
- `KajiAgentTodoPanel` is self-contained and accepts only `[KajiAgentTodoPhase]`, so it is reusable inside a popover (`Kaji/Views/KajiAgent/KajiAgentTodoPanel.swift:3-44`).
- Todo state source of truth is `KajiAgentStore.todoPhases` (`Kaji/Services/KajiAgentStore.swift:41`). It is updated from runtime state snapshots and transcript restore (`Kaji/Services/KajiAgentStore.swift:720-737`) and live `todo_write` tool effects (`Kaji/Services/KajiAgentToolTodoEffect.swift`).
- Subagent/task progress lives in task tool details attached to tool messages: `KajiAgentMessage.taskDetails` (`Kaji/Models/KajiAgentConversationModels.swift`) and rendered inline by `KajiAgentMessageRow` through `KajiAgentTaskToolView` (`Kaji/Views/KajiAgent/KajiAgentMessageRow.swift:79-80`).
- `KajiAgentTaskToolView` delegates to `KajiAgentSubagentListView(layout:)` (`Kaji/Views/KajiAgent/KajiAgentTaskToolView.swift:3-8`). `KajiAgentSubagentListView` already supports inline rows and overflow modals through `KajiModalCoordinator` (`Kaji/Views/KajiAgent/KajiAgentSubagentListView.swift:3-60`).

### Existing reusable UI patterns

- `.kajiPopover(isPresented:preferredEdge:content:)` wraps content in an `NSPopover` with `.transient` behavior (`Kaji/Views/Components/KajiPopover.swift:40-53,88-99`). The popover surface automatically uses `KajiPopoverSurface` with `TranslucentSurface` and Kaji theme tokens (`Kaji/Views/Components/KajiPopover.swift:169-185`).
- `CodingAgentProcessTopBarButton` is the closest existing button+popover pattern: local `showPopover` and `hovered` state, a plain button, `KajiIcon`, count text, hover effect, change feedback, pointer, help/accessibility text, and `.kajiPopover` (`Kaji/Views/TopBar/CodingAgentProcessTopBarButton.swift:3-67`).
- `SidebarActivityBorder` provides an existing animated angular-gradient border for activity state (`Kaji/Views/Sidebar/SidebarActivityBorder.swift:3-36`). Reusing or extracting this pattern avoids creating a parallel visual language.
- `KajiAgentHome.timeline` already uses a bottom-right overlay for “Jump to latest” (`Kaji/Views/KajiAgent/KajiAgentHome.swift:251-258`). The floating task button must not occupy the same exact corner at the same time.

## Root causes

### Scroll issue

The root bug is not the scroll view itself. It is the lock heuristic:

- `distance < 72` means “unlock,” not “near bottom.”
- With small overflow, almost any user scroll-up remains inside 72 px.
- Streaming/task updates then call `handleTailChanged()` and force bottom.

The fix should make the coordinator preserve intentional user scroll-away even when the distance is small.

### Todo/task top placement

The todo panel is inside scroll content, so it consumes vertical height and can create the “slightly scrollable” condition that makes the scroll bug easier to hit. Moving it out of the timeline is not only a UI cleanup; it also reduces scroll-content churn during todo updates.

## Implementation plan

### Phase 1: Harden scroll intent detection

Modify `KajiAgentScrollCoordinator` so auto-scroll only happens when the user is truly pinned to the bottom.

Concrete changes:

1. Replace the single 72 px threshold with hysteresis:
   - `pinnedThreshold`: 8-12 px.
   - `awayThreshold`: 16-24 px.
   - If already locked, stay locked until distance is within `pinnedThreshold`.
   - If unlocked, lock as soon as distance exceeds `awayThreshold`.
2. Add an execution-time guard in scheduled streaming auto-scroll:
   - `handleTailChanged()` may schedule a scroll, but `performScrollToBottom` should only run for non-forced scrolls if `distanceFromBottom <= pinnedThreshold` at execution time.
   - If the user moved away during the 16 ms scheduling window, cancel the auto-scroll path and set `isLocked = true`, `hasUnseenTail = true`.
3. Keep `scrollToBottom(force: true)` as the escape hatch that always clears lock state and scrolls to bottom.
4. Keep new-turn `scrollToTurn` behavior, but ensure it is used only for actual new turns. It currently fires from `.onChange(of: store.turns.last?.id)` (`Kaji/Views/KajiAgent/KajiAgentHome.swift:260-263`), so it should not run on every streaming delta.
5. Remove `KajiAgentTimelineScrollState.swift` after confirming there are no references.

Acceptance criteria:

- If the user scrolls up even 10-20 px while a task/subagent is streaming, Kaji does not force the thread back to the bottom.
- `hasUnseenTail` becomes true when new output arrives while the user is away from the bottom.
- Clicking “Jump to latest” still scrolls to bottom and clears unseen state.
- If the user is already pinned to bottom, streaming output continues to follow the tail.
- No overlapping animated scrolls are introduced; streaming remains non-animated.

Tests:

- Add `KajiAgentScrollCoordinator` unit coverage by extracting threshold decisions into a small pure policy, e.g. `KajiAgentScrollLockPolicy`.
- Test transitions:
  - unlocked + distance 0 -> remains unlocked.
  - unlocked + distance 12/20 -> locks depending chosen threshold.
  - locked + distance 12/20 -> stays locked.
  - locked + distance 0 -> unlocks.
  - scheduled non-forced scroll with distance now away -> does not scroll and marks unseen.

### Phase 2: Create floating task state model

Add a small model that summarizes all data needed by the floating button and popover.

Proposed type:

- `KajiAgentFloatingTaskState`
  - `todoPhases: [KajiAgentTodoPhase]`
  - `taskDetails: [KajiAgentTaskToolDetails]`
  - `todoIndicator: KajiAgentTodoIndicator?`
  - `hasVisibleWork: Bool`
  - `isWorking: Bool`
  - `openTodoCount: Int`
  - `runningSubagentCount: Int`
  - `failedSubagentCount: Int`

Source extraction:

- Todos come from `store.todoPhases`.
- Task details come from scanning visible timeline messages for `message.taskDetails`. Prefer a computed helper on `[KajiAgentTurn]` or a store computed property so the view does not know transcript internals.
- Running state should be derived from active todos/subagents, not only `store.isRunning`, so the button can still show completed/failed work after the agent stops.

Acceptance criteria:

- Button can hide entirely when there are no todos and no task details.
- Button shows active/working state when there are in-progress todos, running/pending subagents, or `store.isRunning` with visible work.
- Popover can render both todos and subagents from one value, avoiding duplicate scans in child views.

Tests:

- Open todos produce `hasVisibleWork == true` and correct open count.
- Completed-only todos return no active indicator if product decision is to hide closed work.
- Running subagent details produce `isWorking == true` even if todos are empty.
- Failed subagents produce visible work and a failure count.

### Phase 3: Build `KajiAgentFloatingTaskButton`

Create a dedicated view under `Kaji/Views/KajiAgent/`.

Behavior:

- Local `@State private var showPopover = false` and `hovered = false`, following `CodingAgentProcessTopBarButton` (`Kaji/Views/TopBar/CodingAgentProcessTopBarButton.swift:7-42`).
- The button body should use existing atoms:
  - `KajiIcon(systemName:)` for the main symbol.
  - `KajiSpinner(size:)` when work is active.
  - count text with monospaced Kaji font for open todo/running subagent count.
  - `KajiTheme.surface`, `KajiTheme.border`, `KajiShape.tileRadius` or a slightly larger rounded rect for button styling.
  - `SidebarActivityBorder` or extracted `KajiActivityBorder` when active work is running.
- Add `.help(...)` and `.accessibilityLabel(...)` equivalent to the removed header pill help (`Kaji/Models/KajiAgentTodoIndicator.swift:13-21`).
- Attach `.kajiPopover(isPresented: $showPopover, preferredEdge: .top)` or `.trailing`; because the button is bottom-right, `.top` is likely safer than `.trailing` for staying inside the window.

Popover content:

- New `KajiAgentFloatingTaskPopover` view.
- Width around 360-420, matching the model popover scale (`KajiAgentHome.modelPopover` uses 360 width in `Kaji/Views/KajiAgent/KajiAgentHome.swift:130-156`).
- Header: “Tasks” or “Tasks & Agents”; compact summary on the right.
- Section 1: subagents, using `KajiAgentSubagentListView` for each active task detail or a combined layout if a single aggregate layout is introduced.
- Section 2: todos, reusing `KajiAgentTodoPanel` initially or extracting its inner rows into a compact `KajiAgentTodoList` so the popover does not inherit the old 760 max width.
- Empty state inside popover should be explicit but normally unreachable if the button hides when there is no work.

Acceptance criteria:

- Floating button appears at bottom-right only when there are todos/task details.
- The active state is visually obvious while work is running: spinner and animated/accent border.
- Popover uses KajiPopover and Kaji theme components, not a custom popover implementation.
- Popover includes all current todo content and task/subagent progress.
- Existing subagent modal actions still work from inside the popover via `KajiModalCoordinator`.

### Phase 4: Move todo/task UI out of the top and timeline

Update `KajiAgentHome`:

1. Remove header todo pill lines (`Kaji/Views/KajiAgent/KajiAgentHome.swift:83-86`).
2. Remove empty-state `KajiAgentTodoPanel` lines (`Kaji/Views/KajiAgent/KajiAgentHome.swift:164-166`).
3. Remove timeline-top `KajiAgentTodoPanel` lines (`Kaji/Views/KajiAgent/KajiAgentHome.swift:208-210`).
4. Add a single bottom-right overlay at the `KajiAgentHome` root `VStack`, not inside the scroll view:
   - It must be outside the timeline scroll content so it does not affect content height.
   - It must coordinate with “Jump to latest.” If both are visible, stack them vertically in a bottom-right control cluster with Jump above Tasks or Tasks above Jump, rather than both using identical bottom/trailing padding.
5. Keep `widget` and `queuedMessages` in the timeline unless separately requested; the user specifically asked to move todos/tasks.

Acceptance criteria:

- No todo/task panel appears at the top of header, empty state, or timeline.
- Floating control is stable across empty, restoring, and populated timeline states.
- Timeline content height no longer changes when only todo phases update.
- “Jump to latest” remains reachable and not overlapped.

### Phase 5: Verification loop

Targeted tests:

- New scroll lock policy tests.
- Floating task state summary tests.
- Existing todo parsing/restoration tests remain passing.
- If component logic is extractable, add tests for hidden/visible button decisions.

Manual/UI validation:

- Start a task with subagents, scroll upward a small amount while output streams, confirm it does not snap back.
- Confirm Jump to latest restores tail following.
- Run a todo-writing task; verify the todo panel appears only in the floating popover.
- Open popover while subagents update; verify content refreshes without closing unexpectedly.
- Verify bottom-right control cluster with both “Jump to latest” and task button visible.

Commands:

- Run targeted Swift tests for new policy/state tests.
- Run `swift build`.
- Run `swift test` if feasible.
- Run `scripts/checks.sh --fix`; current environment previously lacked `swiftformat`, so install/use local formatter if available or report the exact missing prerequisite.

## Recommended implementation order

1. Extract and test `KajiAgentScrollLockPolicy`.
2. Update `KajiAgentScrollCoordinator` to use policy and recheck before non-forced auto-scroll.
3. Add `KajiAgentFloatingTaskState` tests and extraction helpers.
4. Add `KajiAgentFloatingTaskButton` and popover views.
5. Remove inline/header todo renders from `KajiAgentHome` and add the bottom-right control cluster.
6. Update architecture docs to note task/todo state is surfaced through the floating popover and not timeline content.
7. Build, test, fix, repeat.
