# KajiCode Bundling And Kaji Agent Removal Plan

## Goal
Make KajiCode the default separate CLI agent in Kaji without requiring a Kaji app release for every KajiCode CLI update. Kaji should ship the integration layer, installer, updater, hooks, MCP setup, and launch surfaces. KajiCode should ship independently through its own release channel.

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
   - This runtime cannot be deleted until these clients move to KajiCode.

3. Parent Agent and graph
   - Code graph uses `Kaji/Services/KajiCodeGraphAgentCoordinator.swift`.
   - It launches `ParentAgentController` and `ParentAgentProcess`, not `KajiAgentProcess`.
   - Keep `KajiParentAgentRuntime` until KajiCode has equivalent host-tool support for project context, terminal opening, diff opening, verification, and subagent orchestration.

## Release And Update Findings
Kaji release packaging still hard-requires old Kaji Agent artifacts:

- `scripts/build-release.sh` requires `KajiAgentRuntime/kaji-agent-runtime.mjs`, `pi/kaji-agent.mjs`, and `pi/oauth-login.mjs`.
- The same script stages and signs the native Kaji Agent addon through `scripts/stage-kaji-agent-native-addon.sh`.
- `scripts/smoke-release-app.sh` verifies Kaji Agent runtime paths and native addon signatures.

Kaji already has useful managed-install patterns:

- `AIGatewayClaudeCodeRouterInstaller` installs an external npm package into Application Support, writes an install manifest, and supports repair/uninstall.
- `KajiCodeGraphInstaller` installs an optional extension outside the app bundle and keeps its runtime under a Kaji-owned directory.
- Browser and graph MCP installers copy Kaji-owned binaries into `~/.kaji/bin` and write normal user MCP config without global system writes.
- `KajiFileStorage.appSupportDirectory()` is the right root for Kaji-managed state and supports `KAJI_APP_SUPPORT_DIR` for tests.

KajiCode now has independent distribution machinery:

- `make build` produces `./kajicode`.
- `kajicode serve --mcp` works locally.
- `scripts/install.sh` downloads GitHub release archives and verifies `.sha256`.
- `scripts/postinstall.mjs` can download the matching release archive without trusting archive paths.
- `scripts/npm/build-platform-packages.mjs` builds npm wrapper and per-platform payload packages.
- `kajicode update --check` and `kajicode upgrade` already exist, but Kaji should add its own compatibility gate before installing updates.

## Recommended Distribution Model
Use a Kaji-managed, latest-compatible KajiCode install.

Kaji should not blindly run `npm install -g` or always launch whatever `latest` means. Instead, Kaji should fetch a KajiCode update channel manifest, choose the newest version compatible with the installed Kaji integration protocol, download that version, smoke it, then activate it atomically.

Kaji release cadence:

- Kaji release is needed when Kaji-side integration changes.
- Kaji release is not needed for normal KajiCode CLI improvements.
- KajiCode release is enough when the CLI preserves the Kaji integration protocol.

## Update Channel Manifest
Add a KajiCode-published channel file, for example `distribution/kaji-channel.json` in the KajiCode repo or a release asset served from a stable URL. Minimum entry fields: `version`, `protocolVersion`, `minKajiVersion`, optional `maxKajiVersion`, and per-platform assets with `url`, `sha256`, and `size`.

Kaji chooses the highest entry where `schemaVersion` is supported, `protocolVersion` is in Kaji's supported range, `minKajiVersion <= current Kaji version`, `maxKajiVersion` is empty or still allows the current Kaji version, and the current platform asset exists.

## npm Role
npm should stay a public CLI distribution channel, not the primary Kaji app dependency. Users can still run `npm install -g @dishant0406/kajicode`, and KajiCode can keep publishing npm platform packages for terminal users. Kaji can optionally support npm registry tarballs as an update asset type in the channel manifest.

Kaji should avoid requiring npm, Node, global installs, un-gated `@dishant0406/kajicode@latest`, or package lifecycle scripts. If npm tarballs are used, Kaji should download the tarball directly from registry metadata, verify integrity/checksum, extract only known files, smoke the binary, and record the manifest.

## Kaji Managed Install Layout
Install KajiCode under Application Support:

```text
~/Library/Application Support/Kaji/kajicode/
  channel-cache.json
  install-manifest.json
  versions/
    0.4.1/
      macos-arm64/
        kajicode
        helpers/
```

`install-manifest.json` should record active version, previous version, protocol version, source URL, sha256, install time, binary path, smoke result, and hook/MCP setup state.

Install flow: download into staging, verify size/SHA256, extract only expected basenames and directories, set executable permissions, run `kajicode --version`, `kajicode doctor --json` in no-credential mode, run MCP initialize smoke, atomically activate the version, and keep the previous version for rollback.

## Kaji Integration Services
Add a module under `Kaji/Services/CodingAgents/KajiCode/`:

- `KajiCodeChannelClient`: fetch and parse the update channel manifest.
- `KajiCodeCompatibilityPolicy`: select latest compatible version.
- `KajiCodeArchiveDownloader`: download with byte limits and SHA256 verification.
- `KajiCodeArchiveExtractor`: extract only expected files.
- `KajiCodeInstallStore`: read/write managed install manifests.
- `KajiCodeInstaller`: install, repair, activate, rollback, uninstall.
- `KajiCodeRuntimeLocator`: resolve dev override, managed active install, bundled fallback, then PATH fallback.
- `KajiCodeSmokeTester`: verify version, doctor, and MCP initialize.
- `KajiCodeHookInstaller`: install Kaji defaults through KajiCode hook commands or config files.
- `KajiCodeMCPInstaller`: install KajiCode MCP defaults.
- `KajiCodeCommandBuilder`: build terminal launch commands.
- `KajiCodeSettingsView`: show active version, latest compatible version, source, hooks, MCP, update, rollback, repair, and dev override status.

Resolution order: developer override such as `KAJICODE_DEV_BIN`, Kaji-managed active install, optional bundled fallback binary, then PATH fallback.

## Fast Local Development
For fast KajiCode iteration, use a dev override instead of publishing anything:

```bash
cd /Users/dishants/projects/KajiCode
make build
KAJICODE_DEV_BIN=/Users/dishants/projects/KajiCode/kajicode swift run Kaji
```

New KajiCode terminal splits should use the override path immediately.

## Migration Plan
### Phase 1: KajiCode Channel
- Add the KajiCode channel manifest and publish it with each KajiCode release.
- Include protocol, Kaji compatibility, platform asset URLs, SHA256, and sizes.
- Keep GitHub release archives as the first asset source. Add npm tarball support later only if needed.

### Phase 2: Kaji Managed Installer
- Implement the KajiCode channel client, compatibility policy, downloader, extractor, install store, installer, smoke tester, and runtime locator.
- Add one-click install, update, repair, rollback, and uninstall in Settings.
- Do not touch GUI Kaji Agent yet.

### Phase 3: Hooks And MCP Defaults
- Install KajiCode hooks idempotently.
- Prefer stable `kajicode hooks add --user --json` commands.
- Register `kajicode serve --mcp` where needed.
- Preserve user edits and provide uninstall.

### Phase 4: Replace GUI Entry Point
- Change the footer Kaji button to open a terminal split running KajiCode.
- Rename or remove `openKajiAgentSplit`.
- Stop creating `.parentAgent` tabs from that button.

### Phase 5: Move Runtime Consumers
- Add stable KajiCode machine commands for commit messages and meeting notes.
- Replace `GitCommitMessageRuntimeClient`.
- Replace `KajiMeetingNotesAgentClient`.
- Move provider/model settings away from `KajiAgentStore`.

### Phase 6: Remove Old Runtime Packaging
- Delete unused GUI Kaji Agent views, models, stores, process, and runtime locator code.
- Remove `KajiAgentRuntime` build steps and native addon staging.
- Replace release smoke checks with KajiCode installer/updater smoke.
- Update `docs/architecture.md`.

## Validation
Doc-only update: `git diff --check`.

Kaji implementation: focused Swift tests for channel parsing, compatibility selection, archive verification, install manifest writes, rollback, locator resolution, hook install, and MCP install; `scripts/checks.sh --fix`; `scripts/build-release.sh`; `scripts/smoke-release-app.sh`.

KajiCode implementation: `make build`; `make test`; release package and smoke commands; channel manifest validation; npm package smoke; MCP stdio initialize smoke.

## Decision
Kaji should ship a managed KajiCode installer/updater, not a hard-pinned CLI that requires a Kaji release for every KajiCode change. KajiCode should publish independent releases plus a compatibility manifest. Kaji installs the latest compatible version into Application Support, supports a local dev override, and keeps an optional bundled fallback only for offline recovery.
