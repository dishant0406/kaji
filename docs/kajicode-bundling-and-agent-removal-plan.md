# KajiCode Bundling And Kaji Agent Removal Plan

## Goal
Ship Kaji with KajiCode as the default separate CLI agent, provide one-click setup for hooks and MCP defaults, and remove the current native GUI Kaji Agent without breaking commit messages, meeting notes, code graph, notifications, or release packaging.

## Current Agent Surface
Kaji has three related but separate agent systems today.

1. GUI Kaji Agent
   - The footer button starts from `Kaji/Views/Workspace/CLILauncherFooter.swift`.
   - Workspace state creates `.parentAgent` tabs and splits in `Kaji/Models/WorkspaceReducer/TabReducer.swift`.
   - `Kaji/Views/Workspace/TabContentView.swift` renders `KajiAgentHome`.
   - Main code lives under `Kaji/Views/KajiAgent`, `Kaji/Services/KajiAgent*`, `Kaji/Models/KajiAgent*`, and `KajiAgentRuntime`.

2. Kaji Agent runtime consumers
   - Commit generation uses `GitCommitMessageAgent.swift` and `GitCommitMessageRuntimeClient.swift`.
   - Meeting notes use `Kaji/Services/MeetingNotes/Integration/KajiMeetingNotesAgentClient.swift`.
   - Both launch `KajiAgentRuntimeLocator` and `KajiAgentProcess`, then send JSON RPC frames such as `generate_commit_message`, `generate_meeting_notes`, and `validate_meeting_notes_model`.
   - This means the runtime cannot be deleted until these features move to KajiCode.

3. Parent Agent and graph
   - Code graph uses `Kaji/Services/KajiCodeGraphAgentCoordinator.swift`.
   - It launches `ParentAgentController` and `ParentAgentProcess`, not `KajiAgentProcess`.
   - It depends on `KajiParentAgentRuntime` for host tools such as project context, terminal opening, diff opening, verification, and subagent orchestration.
   - Treat this as separate from GUI Kaji Agent removal unless KajiCode grows equivalent host-tool protocol support.

## Release Packaging Findings
Release scripts still hard-require Kaji Agent artifacts.

- `scripts/build-release.sh` builds `KajiAgentRuntime`, parent agent, Rift, Zlob, Monaco, Termy, workers, helpers, and `KajiHookClient`.
- It requires `Kaji/Resources/KajiAgentRuntime/kaji-agent-runtime.mjs`, `Kaji/Resources/pi/kaji-agent.mjs`, and `Kaji/Resources/pi/oauth-login.mjs`.
- It stages and signs the native Kaji Agent addon through `scripts/stage-kaji-agent-native-addon.sh`.
- `scripts/smoke-release-app.sh` verifies bundled Kaji Agent runtime paths and native addon signatures.

GUI removal is not complete until these release checks are replaced with KajiCode checks.

## KajiCode Findings
The fork in `/Users/dishants/projects/KajiCode` is already locally usable.

- `make build` produces `./kajicode`.
- `./kajicode --version` returns a dev build.
- `./kajicode serve --mcp -C /Users/dishants/projects/muxy` responds over MCP and exposes read-only tools by default.
- `./kajicode doctor --json` can run locally, but provider health can fail when API keys or gateway credentials are missing.

KajiCode also has release machinery:

- `Makefile` supports local and multi-platform builds.
- `scripts/install.sh` downloads release tarballs and verifies checksums.
- `scripts/postinstall.mjs` supports npm wrapper install, dry runs, skip download, platform overrides, repository override, and SHA256 verification.
- `cmd/kajicode-release/main.go` exposes release build, package, smoke, and verify commands.

The KajiCode checkout is currently dirty from rebranding work, so Kaji should not pin that tree until KajiCode has its own clean release commit and artifact.

## Bundling Options
### Option A: Download On First Run
Kaji ships without KajiCode, then downloads the matching release when the user clicks install.
Use this as a repair fallback, not the default production path. It keeps the app smaller and lets KajiCode hotfix independently, but first-run setup now depends on network, GitHub availability, proxies, checksums, and a harder version-support story.

### Option B: Build From Source During Kaji Release
Kaji vendors KajiCode source as a submodule or checked-in dependency and builds it in `scripts/build-release.sh`.
Use this only if source-level auditability inside the Kaji repo is required. It is reproducible, but makes Kaji release own Go setup, cross-compilation, longer release time, and submodule friction.

### Option C: Embed Prebuilt Release Artifacts
Kaji release consumes a pinned KajiCode release tarball, verifies checksum, and embeds the binary plus helper files into `Contents/Resources/KajiCode`.
This is the recommended path. It gives the best user experience, works offline after app install, avoids user Bun/npm/Go dependencies, supports app-level codesign/notarization, and lets release smoke verify the actual shipped CLI. The tradeoff is that Kaji must pin KajiCode versions and checksums.

### Option D: npm Wrapper Install
Kaji invokes the KajiCode npm package installer.
Do not use this as the primary Kaji app install path. It reuses existing install logic, but requires Node/npm in a native app flow and adds lifecycle, trust, and environment issues.

### Option E: Build On User Machine
Kaji asks the user machine to clone and build KajiCode locally.
Keep this as a developer override only. It is useful for local fork testing, but requires Go, git, network, and correct user environment.

## Recommended Architecture
Use a signed, bundled KajiCode binary as the default CLI, with idempotent one-click setup.

Add a KajiCode module under `Kaji/Services/CodingAgents/KajiCode/`:

- `KajiCodeBundleLocator`: resolve developer override, bundled resource, managed install, then PATH fallback. Report active path, source, version, and health.
- `KajiCodeInstaller`: install or repair the managed CLI, verify version/checksum, and avoid global system paths.
- `KajiCodeHookInstaller`: install default hooks idempotently. Prefer invoking stable KajiCode hook commands; add those commands in KajiCode first if they do not exist.
- `KajiCodeMCPInstaller`: register `kajicode serve --mcp` as a stdio MCP server, read-only by default, with explicit opt-in for unsafe tools.
- `KajiCodeCommandBuilder`: build safe terminal launch commands for cwd, prompt, mode flags, MCP, and hooks.
- `KajiCodeSettingsView`: replace Kaji Agent settings with install status, bundled version, active version, hook status, MCP status, provider health, and repair actions.

Keep `KajiHookClient` as the notification bridge unless KajiCode replaces it with an equivalent native bridge.

## Migration Plan
### Phase 1: Stabilize KajiCode

- Finish KajiCode fork cleanup.
- Create a clean KajiCode release commit and tag.
- Produce darwin arm64 and x64 artifacts.
- Verify `make build`, release package/smoke, `kajicode --version`, `kajicode doctor --json`, and `kajicode serve --mcp`.

### Phase 2: Bundle KajiCode In Kaji

- Add a KajiCode artifact manifest with version, filenames, sizes, and checksums.
- Stage `Contents/Resources/KajiCode/kajicode` and helper files in `scripts/build-release.sh`.
- Codesign bundled KajiCode binaries during Kaji release signing.
- Update `scripts/smoke-release-app.sh` to verify binary existence, execute bit, version output, no-credential doctor mode, MCP initialize, and signatures.

### Phase 3: Add One-Click Setup

- Build the locator, installer, hook installer, MCP installer, and settings surface.
- Setup should select the active bundled CLI, install or repair hooks, register MCP defaults, and verify provider/config health without requiring a paid-provider request.
- Make repair safe to run repeatedly.

### Phase 4: Replace The GUI Entry Point

- Change the footer Kaji button to open a terminal split running KajiCode in the active project.
- Rename or remove the `openKajiAgentSplit` shortcut.
- Stop creating `.parentAgent` tabs from that button.
- Do not delete `KajiAgentRuntime` yet because commit generation and meeting notes still use it.

### Phase 5: Move Commit Messages To KajiCode

- Add or confirm a stable machine command, preferably `kajicode commit-message --repo <path> --json`.
- Support request fields for staged diff, provider, model, style, and max length.
- Return title, body, confidence, and diagnostics as JSON.
- Replace `GitCommitMessageRuntimeClient`.
- Move commit provider/model settings away from `KajiAgentStore`.
- Add tests for command resolution, request encoding, timeout, unavailable CLI, and invalid JSON.

### Phase 6: Move Meeting Notes To KajiCode

- Add or confirm KajiCode machine commands for `generate_meeting_notes` and `validate_meeting_notes_model`.
- Replace `KajiMeetingNotesAgentClient`.
- Keep recording, transcription, persistence, and coordinator code intact.
- Add tests for synthesis success, validation failure, timeout, and unavailable CLI.

### Phase 7: Keep Graph Separate For Now

- Keep `KajiParentAgentRuntime` while `KajiCodeGraphAgentCoordinator` depends on it.
- Migrate graph later only if KajiCode gets equivalent host tools for project context, coding-agent selection, terminal/split opening, diff opening, verification, and subagent orchestration.

### Phase 8: Remove GUI Kaji Agent Runtime And Packaging
Only after commit generation and meeting notes are migrated:

- Delete GUI Kaji Agent views, models, settings, stores, processes, and runtime locator code.
- Delete unused `KajiAgentRuntime` build steps.
- Remove `scripts/stage-kaji-agent-native-addon.sh` from release packaging.
- Remove Kaji Agent runtime and native addon checks from release smoke.
- Update `docs/architecture.md`.
- Run full release smoke.

## Hook Defaults
Default hook setup should be conservative.

- Enable activity and completion notifications through `KajiHookClient`.
- Enable session metadata hooks for Kaji's activity store.
- Keep shell, write, and tool hooks opt-in if they can mutate files or run commands.
- Store installed hook state in a Kaji-owned config location.
- Provide repair and uninstall actions.
- Detect and preserve user customizations instead of overwriting existing hook config.

## Validation
Doc-only planning change:
- `git diff --check`

Kaji implementation:
- Focused Swift tests for locator, installer, hook installer, MCP installer, and command builder.
- `scripts/checks.sh --fix`
- `scripts/build-release.sh`
- `scripts/smoke-release-app.sh`

KajiCode implementation:
- `make build`
- `make test`
- release package and smoke commands
- MCP stdio initialize smoke
- JSON command smoke for commit messages and meeting notes

## Main Risks

- Removing `KajiAgentRuntime` too early breaks commit messages and meeting notes.
- Release packaging currently enforces Kaji Agent runtime and native addon presence.
- Kaji needs pinned KajiCode versions and checksums because KajiCode is a separate repository.
- Provider health should not require a real paid-provider request during setup.
- Executing the signed bundled binary is safer than copying binaries out of the app bundle.
- Hook installation must be explicit, idempotent, and reversible.

## Decision
Bundle signed KajiCode release artifacts inside Kaji, add one-click setup for hooks and MCP defaults, replace the visible GUI Kaji Agent entry point with a terminal-backed KajiCode split, migrate commit messages and meeting notes onto KajiCode machine commands, keep graph on Parent Agent until KajiCode has equivalent host tools, then remove the old GUI Kaji Agent runtime and release packaging requirements.
