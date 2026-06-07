# Kaji Agent Thread Performance Plan

## Problem

Long Kaji Agent threads slow down during streaming, and the timeline can intermittently render as a blank area. The current UI already uses a lazy container, but the expensive work is not only view creation. Every streaming delta mutates the root transcript array, invalidates the timeline, re-parses growing markdown content, scans all tool groups, and schedules scroll work.

## Source-grounded findings

### Current SwiftUI timeline

- `KajiAgentHome` switches structurally between `emptyState` and `timeline` based on `store.turns.isEmpty` (`Kaji/Views/KajiAgent/KajiAgentHome.swift:42-45`).
- The timeline is `ScrollView` → `LazyVStack` → `ForEach(store.turns)` (`Kaji/Views/KajiAgent/KajiAgentHome.swift:176-204`).
- The last turn receives `minimumHeight: max(0, timelineHeight - 24)` while `timelineHeight` is measured by a `GeometryReader` attached to the same scroll view (`Kaji/Views/KajiAgent/KajiAgentHome.swift:192-210`).
- `tailVersion` changes call `expandNewToolGroups()` and `scrollCoordinator.handleTailChanged()` (`Kaji/Views/KajiAgent/KajiAgentHome.swift:228-230`). `expandNewToolGroups()` scans every turn and every tool group on every tail update (`Kaji/Views/KajiAgent/KajiAgentHome.swift:272-275`).
- `KajiAgentTurnView` eagerly renders every block inside a turn with `ForEach(turn.blocks)` (`Kaji/Views/KajiAgent/KajiAgentTurnView.swift:9-31`).
- `KajiAgentMessageRow` renders incomplete assistant messages through `KajiAgentStreamingMarkdownText`, which eventually feeds `ParentAgentMarkdownText` (`Kaji/Views/KajiAgent/KajiAgentMessageRow.swift:13-20`).
- `ParentAgentMarkdownText.blocks` calls `ParentAgentMarkdownParser.parse(content)` as a computed property on each body evaluation (`Kaji/Views/ParentAgent/ParentAgentMarkdownText.swift:17-19`).

### Current streaming path

- The TypeScript runtime emits every agent event directly to stdout as one JSON line through `session.subscribe(event => output(event))` (`KajiAgentRuntime/src/modes/rpc/rpc-mode.ts:194-197,479-482`).
- `AgentSession` emits `message_update` events synchronously to subscribers before extension handling (`KajiAgentRuntime/src/session/agent-session.ts:1101-1107`).
- Swift reads stdout and decodes every frame on the main actor (`Kaji/Services/KajiAgentProcess.swift:76-80,128-143`).
- `KajiAgentStore` is `@MainActor @Observable`; `message_update` calls `KajiAgentAssistantTimelineApplier.apply` with `turns` and `tailVersion` inout (`Kaji/Services/KajiAgentStore.swift:4-6,455-479`).
- `appendAssistantDelta` bumps `tailVersion` before appending each text or thinking delta to a message string (`Kaji/Services/KajiAgentAssistantTimelineApplier.swift:113-154`).
- `KajiAgentTimeline.updateMessage` replaces the enum value inside the `turns` array on every delta (`Kaji/Services/KajiAgentTimelineMessages.swift:87-95`).
- Tool start currently bumps twice: once in `KajiAgentToolTimelineApplier.start` and once in `KajiAgentTimeline.appendToolToActiveGroup` (`Kaji/Services/KajiAgentToolTimelineApplier.swift:10-26`, `Kaji/Services/KajiAgentTimelineTools.swift:2-15`).

### Likely causes

1. Root-level transcript invalidation: each delta mutates `turns`, so `KajiAgentHome` and its `LazyVStack` dependencies update at token frequency.
2. Full markdown re-parse: streaming text parses the whole accumulated assistant message after the 80 ms debounce; completed rows also re-parse when their parent body is reevaluated.
3. Scroll/layout feedback: `timelineHeight` drives the last turn minimum height while streaming changes content height. This can trigger repeated measurement and relayout.
4. Overlapping scroll tasks: every tail change schedules a delayed animated scroll, while new-turn scrolling, bounds observation, and streaming layout changes are also active (`Kaji/Services/KajiAgentScrollCoordinator.swift:42-104`).
5. Blank teardown window: session switching clears `turns` before `get_messages` returns (`Kaji/Services/KajiAgentStore.swift:249-257`), and the root `if store.turns.isEmpty` can replace the whole scroll view for a frame.

## Web research summary

- Apple documents `LazyVStack` as lazy: it creates items only as needed for rendering. This improves long-list creation cost, but it does not remove the cost of frequent state invalidation, expensive visible rows, or dynamic height measurement. Source: Apple `LazyVStack` docs, https://developer.apple.com/documentation/swiftui/lazyvstack.
- Apple’s WWDC23 “Demystify SwiftUI performance” emphasizes dependency scoping: reduce dependencies, pass only the data a view needs, and avoid forcing list/table identity work by using variable row counts inside `ForEach`. Source: https://developer.apple.com/videos/play/wwdc2023/10160/.
- Apple’s WWDC23 “Discover Observation in SwiftUI” explains that `@Observable` tracks properties read by a view. This helps only when mutable state is split so unchanged rows do not depend on the root array that changes every delta. Source: https://developer.apple.com/videos/play/wwdc2023/10149/.
- Apple’s modern scroll APIs for macOS 14+ use `scrollPosition` with `scrollTargetLayout()` for identity-based scrolling, avoiding AppKit subtree searches for SwiftUI scroll targets. Sources: https://developer.apple.com/documentation/swiftui/scrollposition and https://developer.apple.com/documentation/swiftui/view/scrolltargetlayout%28isenabled:%29.
- Public macOS SwiftUI reports match the shape of this issue: `ScrollView + LazyVStack` with dynamic row heights can jump or render poorly when row heights vary and update during scrolling. This supports treating high-frequency dynamic-height streaming inside the lazy stack as a risk, not relying on lazy view creation alone. Example: https://stackoverflow.com/questions/74853727/swiftui-lazyvstack-that-contains-items-of-different-heights-does-not-work-well.

## Design direction

Do not treat this as “replace `VStack` with `LazyVStack`.” Kaji already has `LazyVStack`. The fix should make the transcript renderer incremental:

1. Coalesce runtime deltas before publishing UI state.
2. Split transcript state into stable row models so one streaming row can update without replacing the whole `turns` array.
3. Render completed history through a virtualized/static region and isolate the live streaming tail.
4. Replace custom AppKit scroll targeting and height feedback with SwiftUI scroll target state where possible.
5. Remove blank-producing structural swaps during session restore/switch.

## Proposed implementation phases

### Phase 1: Instrument and reproduce

Add a narrow debug-only stress path before changing architecture.

- Add signposts or scoped timings around:
  - `KajiAgentProcess.consume`
  - `KajiAgentStore.handleEvent`
  - assistant/tool applier delta paths
  - `ParentAgentMarkdownParser.parse`
  - scroll coordinator scheduled and executed scrolls
- Add a local stress fixture that can replay a synthetic long thread and high-rate streaming deltas through the store without a provider.
- Acceptance:
  - The stress run can reproduce slow updates with hundreds of turns and a streaming assistant response.
  - Logs show per-delta main-actor decode/mutate/render pressure and markdown parse count.

### Phase 2: Stop blank scroll teardown

Fix the blanking risks that are independent of virtualization.

- Replace the root `if store.turns.isEmpty { emptyState } else { timeline }` with a stable container:
  - keep the scroll view mounted;
  - overlay the empty state only when no transcript is loaded and not restoring;
  - preserve the existing scroll surface through transitions.
- Change `switchSession(path:)` so it does not clear `turns` until replacement messages are ready. Use an `isRestoringTranscript` flag and atomically replace transcript plus active turn after `get_messages` succeeds.
- Keep `clear()` behavior for explicit new thread, but make the UI state explicit instead of relying on a transient empty `turns` array.
- Remove or redesign the `timelineHeight` → last-turn `minimumHeight` feedback loop. Prefer a bottom spacer/sentinel or `defaultScrollAnchor`/`scrollPosition` behavior over measuring the scroll view and feeding that height back into the active row.
- Acceptance:
  - Switching sessions does not unmount the scroll view while messages are loading.
  - Streaming no longer changes a measured scroll-view height that feeds directly into the active turn’s minimum height.

### Phase 3: Coalesce streaming updates at the store boundary

Throttle UI publication, not runtime correctness.

- Introduce a main-actor `KajiAgentTimelineUpdateCoalescer` or equivalent store helper.
- For `message_update` events with `text_delta` or `thinking_delta`:
  - append deltas into a pending buffer keyed by active turn + content index + kind;
  - schedule a flush at a fixed cadence, likely 33-50 ms;
  - flush immediately on `message_end`, turn end, stop, clear, session switch, or when a new content block starts.
- For `tool_execution_update` events:
  - coalesce preview/full output regeneration by tool call ID;
  - avoid recomputing `KajiAgentToolOutputPreview.make` for every partial output if newer output supersedes older output before the next UI flush.
- Keep runtime/session persistence unchanged. Only the Swift UI-facing timeline publication is coalesced.
- Acceptance:
  - 100 sequential text deltas produce the exact same final message text.
  - `tailVersion` increments at flush cadence, not per token.
  - `message_end` cannot leave buffered text undisplayed.
  - Tool output final state remains exact.

### Phase 4: Introduce stable render rows

Make SwiftUI dependencies match the actual changed unit.

- Add a render model layer that flattens turns into stable rows:
  - `userMessage`
  - `assistantMessage`
  - `thinkingMessage`
  - `toolGroupHeader`
  - `toolMessage`
  - `eventMessage`
  - `bottomAnchor`
- Each row should have a stable UUID from the underlying message/group, not content-derived identity.
- Prefer per-row `@Observable final class` models for mutable streaming fields, with the array changing only when rows are inserted/removed/reordered.
- Keep the existing `KajiAgentTurn` transcript model if it is still needed for restoration/tests, but avoid using the mutable tree directly as the SwiftUI render dependency for every row.
- Replace `expandNewToolGroups()` full transcript scan with insertion-time behavior. When a new group row appears, mark it expanded unless its ID is already in `collapsedToolGroups`.
- Acceptance:
  - Updating one assistant delta mutates one row model and does not replace the render row array.
  - Completed older rows do not observe live streaming text.
  - Tool-group expansion no longer scans every turn on every tail update.

### Phase 5: Virtualize completed history and isolate the live tail

Use SwiftUI laziness where it helps and avoid lazy-stack dynamic-height churn where it hurts.

- Split rendering into:
  - completed/history rows: mostly static, virtualized with `LazyVStack` or `List`;
  - live tail rows: a small non-lazy `VStack` at the bottom, updated by streaming.
- Flatten row structure before rendering so `ForEach` produces one row per element. This matches Apple’s `List`/`Table` identity guidance and avoids variable row counts inside the list body.
- Evaluate two renderers behind an internal policy:
  - `ScrollView + LazyVStack + scrollTargetLayout()` for current visual fidelity;
  - `List` with `.plain` style for very long mostly-static history if profiling shows better macOS memory behavior.
- Use a `KajiAgentTranscriptVirtualizationPolicy`:
  - always render the live tail and recent N completed rows eagerly enough for smooth streaming;
  - virtualize older rows through the history renderer;
  - optionally collapse very old tool outputs by default while keeping their summary rows visible.
- Do not implement content-derived `.id`, random `.id`, or array/count `.id` resets.
- Acceptance:
  - A transcript with hundreds of turns keeps memory and body-update count bounded while streaming the last response.
  - The active streaming response stays visible and responsive even when older history is long.
  - Expanding old tool output hydrates only that row/group.

### Phase 6: Replace scroll coordination with state-driven targets

Reduce AppKit interop and animation conflicts.

- Replace `KajiAgentTurnAnchor` plus recursive `findView(withIdentifier:)` where possible with SwiftUI `.id`, `.scrollTargetLayout()`, and `ScrollPosition`/`scrollPosition` on macOS 14+.
- Keep an AppKit fallback only if a measured macOS issue requires it.
- Use non-animated scroll-to-bottom during streaming flushes when the user is already pinned to bottom.
- Animate only explicit user actions such as “Jump to latest” or new-turn navigation.
- Represent lock state as “user is away from bottom” from scroll position/visible bottom distance; do not schedule scroll tasks while locked.
- Acceptance:
  - Streaming flushes cannot pile up overlapping 0.22 s animations.
  - Scroll-to-turn no longer recursively walks the NSView subtree for every target.
  - `hasUnseenTail` still appears when the user scrolls away from the bottom.

### Phase 7: Cache markdown parsing

Remove repeated full parsing from unchanged rows.

- Add a small row-level markdown cache keyed by message ID plus content revision, not by global thread version.
- For completed messages, parse once when completion/final text is applied.
- For streaming messages, parse only at the coalesced render cadence.
- Avoid global unbounded caches; row models can own their parsed blocks and drop them when deallocated.
- Acceptance:
  - Completed messages are not re-parsed when unrelated rows stream.
  - Streaming parse count follows flush count, not raw token count.

### Phase 8: Tests and verification

Add tests before relying on the new behavior.

- Swift Testing unit tests:
  - coalescer preserves text order and final content;
  - coalescer flushes before `message_end` finalization;
  - tool output coalescing preserves final preview/full output/truncation;
  - render-row identity remains stable across text changes;
  - insertion-time tool-group expansion replaces full transcript scans;
  - session switch keeps old transcript until restoration succeeds.
- UI/performance validation:
  - stress replay with 500+ turns and a high-rate streaming response;
  - verify no blank timeline during stream, session switch, or jump-to-latest;
  - verify scrolling away from the bottom does not auto-scroll until Jump to latest;
  - record before/after body update counts and markdown parse counts.
- Run `scripts/checks.sh --fix` after implementation, as required by repo policy.

## Recommended order

1. Phase 1 instrumentation.
2. Phase 2 blank-teardown and height-feedback fixes.
3. Phase 3 coalescing.
4. Phase 7 markdown cache if measurements still show parse cost dominating, or in parallel with Phase 4 if row model ownership is being introduced.
5. Phase 4 stable render rows.
6. Phase 5 history/live-tail virtualization.
7. Phase 6 scroll-position migration.
8. Phase 8 tests and stress validation across the whole path.

## Key decisions

- Keep runtime event protocol exact. Do not drop or merge events in `KajiAgentRuntime` stdout until Swift-side coalescing has proven insufficient.
- Do not migrate directly to `List` as the first change. The current bug is caused by invalidation and dynamic-height streaming pressure; a direct `List` swap may hide the symptom while preserving per-token state churn.
- Do isolate the active streaming tail from completed history. This gives the biggest correctness/performance win while preserving visual control.
- Do replace content-height feedback and overlapping scroll animations before deeper virtualization, because those are credible blank-screen causes even with a better renderer.
