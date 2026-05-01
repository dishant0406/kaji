# Architecture

Droid is a macOS-only SwiftUI app. It embeds upstream libghostty through `GhosttyKit.xcframework` and keeps all app behavior inside the `Droid/` executable target.

## Repo Shape

```text
Droid/                       App target
DroidHookClient/             Native provider hook helper
GhosttyKit/                  C module exposing ghostty.h
GhosttyKit.xcframework/      Built libghostty artifact from ghostty-org/ghostty
Tests/DroidTests/            Swift Testing suite
docs/                        Project docs
scripts/                     Setup, checks, packaging
```

There is no iOS companion target, no shared protocol package, and no remote server layer.
`Droid/Resources/HugeIcons/` carries the bundled Hugeicons free stroke-rounded font and CSS map used by the app icon wrapper.

## Core Runtime

- `Droid/DroidApp.swift` wires the app scene graph, stores, in-app settings modal flow, and app delegate lifecycle.
- `DroidHookClient/` is a native Swift executable bundled beside the app binary. Provider hooks call it directly, and it posts normalized provider events to Droid through macOS `DistributedNotificationCenter`.
- `Droid/Services/AppEnvironment.swift` builds the concrete dependencies used by the app state.
- `Droid/Models/AppState.swift` owns project selection, worktree selection, workspace tabs, split trees, and workspace persistence. Project selection is separate from workspace creation, so a selected project can render an empty state until the first tab is opened.
- `Droid/Models/WorkspaceReducer.swift` is the state transition layer for workspace tabs, panes, splits, and focus.
- `Droid/Services/GhosttyService.swift` owns the single `ghostty_app_t` instance and global Ghostty callbacks.
- `Droid/Views/Terminal/GhosttyTerminalNSView.swift` is the AppKit bridge that creates and drives each `ghostty_surface_t`, including focus and occlusion updates so hidden panes can stay mounted without continuing to render at full cost.
- `Droid/Views/Terminal/TerminalViewRegistry.swift` keeps terminal views alive across SwiftUI updates.

## Workspace Model

```text
Project -> Worktree -> WorktreeWorkspace -> WorkspaceTab -> SplitNode -> TabArea -> TerminalTab
```

- A `Project` is a top-level folder the user adds to Droid.
- A `Worktree` is either the primary project checkout or a git worktree discovered or created for that project.
- `WorktreeWorkspace` owns the ordered top-level tabs for a worktree and remembers which workspace tab is active.
- `WorkspaceTab` is the user-facing tab in the title bar. It owns one full-canvas split tree plus the focused pane inside that tree.
- `SplitNode` stores the pane tree inside one workspace tab.
- `TabArea` remains the leaf model used by the split tree, but after the tab rewrite it acts as a pane container for one active content stack rather than as the app's primary tab concept.
- `TerminalTab` is the content model hosted by a leaf pane and can represent a terminal, editor, VCS view, or diff viewer.
- `TabDragCoordinator` now serves pane-level arrangement only. Title-bar tabs are workspace tabs, not pane-local tabs.

Workspace state is persisted per worktree so every project can keep separate workspace tabs, split layouts, focus state, terminal sessions, editor tabs, and VCS layouts across launches. A project can also remain selected with no workspace root when its tabs are closed or before any tab has been opened.

## Major Subsystems

- Terminal: `GhosttyTerminalNSView`, `TerminalPane`, `TerminalSearchBar`, and `GhosttyRuntimeEventAdapter`. `TerminalPane` keeps terminal views mounted for session continuity while propagating SwiftUI visibility into Ghostty occlusion state, and the embedded bridge now coalesces Ghostty wakeups plus precise scroll bursts before they cross the AppKit-to-libghostty boundary. `GhosttyPerf` adds unified-log signposts around `ghostty_app_tick()` and emits runtime events for wakeup coalescing and scroll flush batches so Instruments and `./script/build_and_run.sh --telemetry` can inspect the hot path.
- Editor: `EditorTabState`, `CodeEditorRepresentable`, `TextBackingStore`, and the syntax highlighter pipeline under `Droid/Syntax/`.
- Git and VCS: `GitRepositoryService`, `GitWorktreeService`, `VCSTabState`, and the attached source-control panel under `Droid/Views/VCS/`.
- Projects and worktrees: `ProjectStore`, `WorktreeStore`, `ProjectOpenService`, and `WorktreeSetupRunner`.
- Workspace navigation: `FileSearchService`, `PaletteOverlay`, `QuickOpenOverlay`, `AskOverlay`, and `WorktreeSwitcherOverlay` handle indexed quick-open, cross-project prompt dispatch, and worktree switching. `AskOverlay` reuses the command-palette shell, supports slash commands, and also accepts inline routing annotations like `:p:`, `:wt:`, `:t:`, and `:s:` inside the query field for hands-free targeting. `AskCommandDispatcher` routes prompt text into existing terminal sessions when possible and falls back to opening a new provider session before sending.
- Notifications and activity: `NotificationStore`, `NotificationNavigator`, `ProviderEventReceiver`, `ProviderEventDispatcher`, `NotificationIntegrationStore`, `NotificationEndpointSender`, `NotificationRouteSoundResolver`, `NotificationDisplayTextResolver`, `CodexSessionMonitor`, `CodexOutboundNotificationCoordinator`, `AIActivityStore`, `AIActivitySocketRouter`, `SystemWakeCoordinator`, `ResourceMonitorService`, `ProcessResourceSampler`, and the AI-provider hook installers under `Droid/Services/Providers/`. Built-in Codex, Claude Code, and OpenCode integrations emit into Droid through `DroidHookClient` and `DistributedNotificationCenter`; provider hooks do not install shell notification scripts or interpreter one-liners. Codex installs first-party `UserPromptSubmit` and `Stop` activity hooks in `~/.codex/hooks.json`, while completion notifications come from `CodexSessionMonitor` reading Codex session JSONL files in-process. Claude Code installs `UserPromptSubmit`, `Stop`, `Notification`, and `PermissionRequest` hooks in `~/.claude/settings.json`, and OpenCode's plugin listens to `session.status`, `question.asked`, and `permission.asked` events so the sidebar only shows activity while a provider is actually in flight instead of for the whole terminal process lifetime.
- Agent Mission Control: `AgentMissionControlPanel` is a sidebar footer popover that turns `AgentRunStore` and provider notifications into task-level rows. `AgentRunStore` is the source of truth for provider runs, preserving pane, provider, project, worktree, worktree path, confidence, lifecycle status, changed-file evidence, verification state, recent events, and bounded control-action records in `agent-runs.json`; interrupted open runs reload as stale so restart never shows old work as actively running. `AgentRunMissionControlSnapshotBuilder` renders run-backed rows first and keeps provider notifications as fallback rows when no run exists for that pane. Live provider transcript snippets arrive through provider events and stay attached to both the legacy active activity and the new run model in memory. Completed runs capture a bounded git changed-file snapshot only when the worktree is not shared by another active run; overlapping runs in the same worktree are marked `shared worktree` so Droid does not falsely attribute combined git changes to one agent. `AgentControlCenter` owns row action capabilities and execution for jump, reply, stop, new run, resume, verification, file open, and diff review so the SwiftUI views only render supported controls. `AgentMissionControlRow` keeps changed-file evidence collapsed by default, expands inline to show file paths, statuses, stats, attribution warnings, verification output, per-file open/diff actions, and a compact control tray. Reply and stop require a live exact-pane terminal; stop sends provider-specific Escape key events, with OpenCode receiving two Escapes and other providers receiving one; new run opens a fresh provider tab in the run worktree; resume is shown only when provider session metadata is available. Evidence actions first activate the run's project and worktree so files and diffs open in the right workspace. The initial verification runner detects Swift packages and executes `swift build && swift test` in the run worktree while storing the resulting status and trimmed output on the run. `AgentMissionControlNavigator` jumps from a row back to the owning pane or notification context.
- Settings and theming: `DroidConfig`, `ThemeService`, `AppTypographySettings`, `KeyBindingStore`, `CLILauncherSettings`, `HugeIconCatalog`, `HugeIconFont`, and the views under `Droid/Views/Settings/` and `Droid/Views/Themes/`. Shared micro controls such as `DroidInput`, `DroidSelect`, `DroidSwitch`, and `DroidButtonStyle` live under `Droid/Views/Components/` and use only `DroidTheme` tokens so form surfaces do not fall back to native control chrome. `DroidTheme` derives primary, secondary, tertiary, elevated, and chrome background layers from the active Ghostty theme, so the bundled `Droid` terminal theme also defines the default SwiftUI hierarchy instead of a flat two-tone shell. `AppTypographySettings` owns the global font family and base font size for both SwiftUI and terminal defaults, and shared `droidFont` modifiers scale UI text relative to that terminal-driven base. Theme management now supports creating user themes, importing external Ghostty themes, and exporting any discovered theme from the in-app picker. Enabled CLI launchers are exposed in the active workspace footer and open terminal tabs with their configured startup commands.
- Updates: `UpdateService` integrates Sparkle for macOS app updates.

## Persistence

Droid stores app data under `~/Library/Application Support/Droid/`.

- `projects.json`: tracked projects
- `worktrees/*.json`: per-project worktree metadata
- workspace persistence files: tabs, splits, and selection state
- notification persistence files used by `NotificationStore`
- `notification-integrations.json`: outbound notification destinations and routing rules
- `agent-runs.json`: recent Agent Mission Control runs, evidence, verification state, and action records
- `ghostty.conf`: Droid-managed Ghostty config snapshot with theme, app-owned terminal typography, a default scrollback cap for large-output sessions, and editor-like cursor interaction defaults
- `~/.config/ghostty/themes/*`: imported and user-created Ghostty theme files managed by `ThemeService`
- `cli-launchers.json`: enabled CLI footer launchers and their commands

The source repo may also contain `.droid/worktree.json` files inside user projects. Those files define setup commands for newly created worktrees.

## Ghostty Integration

`scripts/setup.sh` builds `GhosttyKit.xcframework` from the official `ghostty-org/ghostty` repository, then syncs Ghostty's `shell-integration` and compiled `terminfo` runtime resources into `Droid/Resources/ghostty/` so packaged app builds do not depend on a separate Ghostty.app install for terminal capabilities.

The app only uses the upstream public Ghostty embedding API exposed through `GhosttyKit/ghostty.h`.
