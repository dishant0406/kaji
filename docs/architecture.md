# Architecture

Droid is a macOS-only SwiftUI app. It embeds upstream libghostty through `GhosttyKit.xcframework` and keeps all app behavior inside the `Droid/` executable target.

## Repo Shape

```text
Droid/                       App target
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
- `Droid/Services/AppEnvironment.swift` builds the concrete dependencies used by the app state.
- `Droid/Models/AppState.swift` owns project selection, worktree selection, tab and split trees, and workspace persistence. Project selection is separate from workspace creation, so a selected project can render an empty state until the first tab is opened.
- `Droid/Models/WorkspaceReducer.swift` is the state transition layer for tabs, panes, splits, and focus.
- `Droid/Services/GhosttyService.swift` owns the single `ghostty_app_t` instance and global Ghostty callbacks.
- `Droid/Views/Terminal/GhosttyTerminalNSView.swift` is the AppKit bridge that creates and drives each `ghostty_surface_t`.
- `Droid/Views/Terminal/TerminalViewRegistry.swift` keeps terminal views alive across SwiftUI updates.

## Workspace Model

```text
Project -> Worktree -> SplitNode -> TabArea -> TerminalTab
```

- A `Project` is a top-level folder the user adds to Droid.
- A `Worktree` is either the primary project checkout or a git worktree discovered or created for that project.
- `SplitNode` stores the pane tree for one worktree.
- Each `TabArea` owns ordered tabs inside one pane.
- `TerminalTab` can represent a terminal, editor, VCS tab, or diff viewer tab.

Workspace state is persisted per worktree so every project can keep separate terminal, editor, and VCS layouts across launches. A project can also remain selected with no workspace root when its tabs are closed or before any tab has been opened.

## Major Subsystems

- Terminal: `GhosttyTerminalNSView`, `TerminalPane`, `TerminalSearchBar`, and `GhosttyRuntimeEventAdapter`.
- Editor: `EditorTabState`, `CodeEditorRepresentable`, `TextBackingStore`, and the syntax highlighter pipeline under `Droid/Syntax/`.
- Git and VCS: `GitRepositoryService`, `GitWorktreeService`, `VCSTabState`, and the attached source-control panel under `Droid/Views/VCS/`. Droid no longer supports separate VCS tabs or windows; source control always opens as the attached side panel for the active worktree.
- Projects and worktrees: `ProjectStore`, `WorktreeStore`, `ProjectOpenService`, and `WorktreeSetupRunner`.
- Notifications: `NotificationStore`, `NotificationNavigator`, and `NotificationSocketServer`.
- Settings and theming: `DroidConfig`, `ThemeService`, `KeyBindingStore`, `CLILauncherSettings`, `HugeIconCatalog`, `HugeIconFont`, and the views under `Droid/Views/Settings/` and `Droid/Views/Themes/`. Shared micro controls such as `DroidInput`, `DroidSelect`, `DroidSwitch`, and `DroidButtonStyle` live under `Droid/Views/Components/` and use only `DroidTheme` tokens so form surfaces do not fall back to native control chrome. `DroidTheme` derives primary, secondary, tertiary, elevated, and chrome background layers from the active Ghostty theme, so the bundled `Droid` terminal theme also defines the default SwiftUI hierarchy instead of a flat two-tone shell. Theme management now supports creating user themes, importing external Ghostty themes, and exporting any discovered theme from the in-app picker. Enabled CLI launchers are exposed in the active workspace footer and open terminal tabs with their configured startup commands.
- Updates: `UpdateService` integrates Sparkle for macOS app updates.

## Persistence

Droid stores app data under `~/Library/Application Support/Droid/`.

- `projects.json`: tracked projects
- `worktrees/*.json`: per-project worktree metadata
- workspace persistence files: tabs, splits, and selection state
- notification persistence files used by `NotificationStore`
- `ghostty.conf`: Droid-managed Ghostty config snapshot with theme and default terminal typography
- `~/.config/ghostty/themes/*`: imported and user-created Ghostty theme files managed by `ThemeService`
- `cli-launchers.json`: enabled CLI footer launchers and their commands

The source repo may also contain `.droid/worktree.json` files inside user projects. Those files define setup commands for newly created worktrees.

## Ghostty Integration

`scripts/setup.sh` builds `GhosttyKit.xcframework` from the official `ghostty-org/ghostty` repository, then syncs Ghostty's `shell-integration` and compiled `terminfo` runtime resources into `Droid/Resources/ghostty/` so packaged app builds do not depend on a separate Ghostty.app install for terminal capabilities.

The app only uses the upstream public Ghostty embedding API exposed through `GhosttyKit/ghostty.h`.
