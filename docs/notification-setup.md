# Notification Setup

Kaji's coding-agent integrations use the bundled `KajiHookClient` helper. The helper is a native Swift executable inside the app bundle and posts normalized events to Kaji through macOS `DistributedNotificationCenter`.

## Built-In Integrations

Toggle agents under **Settings -> Coding Agents**. Kaji installs enabled agent hooks that call the native helper directly:

```bash
/Applications/Kaji.app/Contents/MacOS/KajiHookClient send custom "$KAJI_PANE_ID" "Build finished" "All tests passed"
```

Built-in agent hook behavior lives under `Kaji/Services/CodingAgents/<AgentName>/`. Codex completion notifications come from Kaji's native `CodexSessionMonitor`, which reads Codex session JSONL files in-process. Kaji no longer installs Codex `notify` shell hooks.

## Environment

Every terminal spawned by Kaji exports:

```bash
KAJI_HOOK_CLIENT_PATH
KAJI_INSTANCE_ID
KAJI_PANE_ID
KAJI_PROJECT_ID
KAJI_WORKTREE_ID
KAJI_WORKTREE_PATH
```

Use `KAJI_HOOK_CLIENT_PATH` for custom tools running inside Kaji panes.

## Sending A Custom Event

```bash
if [ -n "${KAJI_HOOK_CLIENT_PATH:-}" ]; then
  "$KAJI_HOOK_CLIENT_PATH" send custom "${KAJI_PANE_ID:-}" "Build finished" "All tests passed"
fi
```

Arguments for `send`:

| Argument | Required | Description |
| --- | --- | --- |
| `type` | yes | Source identifier. Unknown values are shown generically. |
| `paneID` | no | Target pane. Use `$KAJI_PANE_ID` inside a Kaji terminal. |
| `title` | yes | Notification title. |
| `body` | no | Notification body. The helper strips delimiters and newlines. |

## Provider Hook Commands

Claude Code hooks use:

```bash
"$KAJI_HOOK_CLIENT_PATH" claude-hook userpromptsubmit
"$KAJI_HOOK_CLIENT_PATH" claude-hook stop
"$KAJI_HOOK_CLIENT_PATH" claude-hook notification
"$KAJI_HOOK_CLIENT_PATH" claude-hook permissionrequest
```

Codex activity hooks use:

```bash
"$KAJI_HOOK_CLIENT_PATH" codex-activity codex start
"$KAJI_HOOK_CLIENT_PATH" codex-activity codex stop
```

OpenCode's plugin calls the same helper with `send` for activity, transcript, and completion events. New coding-agent modules should either install native hooks through their `CodingAgentModule` or call `send`/`codex-activity` directly from their own integration script.

## Delivery Settings

Kaji respects the user's choices under **Settings -> Notifications**:

- **Toast** shows an in-app banner.
- **Sound** plays the selected notification sound.
- **Position** controls toast placement.
- **Destinations** can forward normalized events to `ntfy` or custom HTTP webhooks.
- **Rules** match by source and event type before fan-out.

Notifications targeting the currently focused pane still show toast and sound, but they do not create an unread badge for that active tab.
