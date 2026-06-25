# Kaji Microinteraction Research

Date: 2026-05-30

## Interaction Inventory Snapshot

The deep interaction audit covered every major user-facing surface in Kaji:

- Global shell, top bar, app commands, keyboard shortcuts, overlays, modals, alerts, toasts, and window-level mouse navigation.
- Workspace pane tree, tab strip, pane headers, split dividers, side panel resize handles, drop zones, footer controls, and shortcut reference popovers.
- Terminal surface interactions, Ghostty mouse and keyboard forwarding, terminal search, context menus, file drops, and footer terminal transitions.
- Browser tabs, toolbar, device selector, page text panel, native browser surface focus, page stack, navigation, automation, and read-page actions.
- Editor pane focus, search and replace, markdown modes, outline, inline edit, code editor gutter, fold controls, text selection, editing shortcuts, and status surfaces.
- Sidebar project and worktree rows, project context actions, logo cropper, footer controls, notifications, resource monitor, Agent Mission Control, and AI usage controls.
- Ports and coding-agent process monitors, including refresh/filter/kill flows and destructive confirmations.
- Shared controls: buttons, switches, sliders, selects, inputs, text areas, popovers, palettes, reorderable stacks, modal overlays, secondary click, and middle click helpers.
- Ask overlay, command palette, Quick Open, worktree switcher, Agent Command Center, git/script/task/commit flows, attachment interactions, and keyboard navigation.
- Settings, themes, notification destinations/routes, shortcuts, language packs, extensions, coding agents, AI usage, and editor/terminal preferences.
- VCS, branches, PRs, commit area, file rows, history, diff viewer, hunk expansion, diff comments, staging, discard, pull, push, and merge confirmations.
- Code graph panes, graph canvas gestures, zoom controls, version picker, graph agent panel, file tree, previews, markdown links, problems, Parent Agent, Agent Instructions, and MCP server control.

## Highest-Value Animation Backlog

1. Standardize interaction primitives first: `IconButton`, `KajiButton`, `KajiSwitch`, `KajiSelect`, `SegmentedPicker`, `KajiInput`, `KajiSlider`, `KajiPopover`, and `PaletteOverlay`.
2. Animate workspace tabs: active underline, reorder lift/drop, close reveal, rename expansion, pinned/unread badge transitions.
3. Animate pane operations: focus ring, split divider hover/drag, split creation, drop-zone morph, pane move snap.
4. Animate overlays and palettes: unified scale/fade, highlighted row movement, async loading skeletons, selected-row flash before dismissal.
5. Animate Ask and Agent flows: attachment chips, target chips, mode transitions, runner output, commit stages, reply composer.
6. Animate VCS: file row action reveal, section disclosure, hunk expansion, PR/branch status, diff comment bubbles.
7. Animate editor: search/replace expansion, fold/unfold, outline slide, active-line pulse, inline edit generation/apply states.
8. Animate sidebar: project/worktree selection, context menus, badge counts, Mission Control evidence disclosure, AI usage pins.
9. Animate graph/browser/terminal specialized surfaces: graph node selection/zoom, browser loading/tab selection, terminal drop/search/footer.
10. Add stronger feedback for destructive actions: kill process, discard changes, delete branch/worktree/server, remove project, and pkill patterns.

## Native Swift Microinteraction Library Research

Recommended shortlist for Kaji:

- `Pow` by Emerge Tools: SwiftUI-first change effects and transitions. Best fit for Kaji's microinteraction layer.
- `SwiftUI-Shimmer`: small modifier for loading skeletons and async states. Good fit for palettes, graph loading, code graph, VCS, and settings install flows.
- `FluidGradient`: CoreAnimation-backed animated gradients. Useful only for subtle atmospheric surfaces because Kaji should stay terminal-native and energy efficient.
- `Lottie`: mature vector animation runtime. Use sparingly for branded success/empty states, not for everyday control feedback.
- `Rive`: interactive state-machine animations. Powerful but heavy; use only if Kaji needs designer-authored animated icons or complex interactive illustrations.

Preferred adoption strategy:

1. Build a local `KajiMotion` layer over native SwiftUI animation tokens.
2. Add `Pow` first if external effects are needed.
3. Add `SwiftUI-Shimmer` only if Kaji needs polished loading skeletons quickly.
4. Avoid Lottie/Rive unless there is a concrete designed asset pipeline.
5. Keep AppKit/Ghostty/WebKit surfaces native and animate their surrounding SwiftUI chrome instead of trying to animate embedded surfaces directly.
