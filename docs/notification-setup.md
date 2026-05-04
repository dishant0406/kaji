# Notification Setup

Droid's coding-agent integrations use the bundled `DroidHookClient` helper. The helper is a native Swift executable inside the app bundle and posts normalized events to Droid through macOS `DistributedNotificationCenter`.

## Built-In Integrations

Toggle agents under **Settings -> Coding Agents**. Droid installs enabled agent hooks that call the native helper directly:

```bash
/Applications/Droid.app/Contents/MacOS/DroidHookClient send custom "$DROID_PANE_ID" "Build finished" "All tests passed"
```

Built-in agent hook behavior lives under `Droid/Services/CodingAgents/<AgentName>/`. Codex completion notifications come from Droid's native `CodexSessionMonitor`, which reads Codex session JSONL files in-process. Droid no longer installs Codex `notify` shell hooks.

## Environment

Every terminal spawned by Droid exports:

```bash
DROID_HOOK_CLIENT_PATH
DROID_INSTANCE_ID
DROID_PANE_ID
DROID_PROJECT_ID
DROID_WORKTREE_ID
DROID_WORKTREE_PATH
```

Use `DROID_HOOK_CLIENT_PATH` for custom tools running inside Droid panes.

## Sending A Custom Event

```bash
if [ -n "${DROID_HOOK_CLIENT_PATH:-}" ]; then
  "$DROID_HOOK_CLIENT_PATH" send custom "${DROID_PANE_ID:-}" "Build finished" "All tests passed"
fi
```

Arguments for `send`:

| Argument | Required | Description |
| --- | --- | --- |
| `type` | yes | Source identifier. Unknown values are shown generically. |
| `paneID` | no | Target pane. Use `$DROID_PANE_ID` inside a Droid terminal. |
| `title` | yes | Notification title. |
| `body` | no | Notification body. The helper strips delimiters and newlines. |

## Provider Hook Commands

Claude Code hooks use:

```bash
"$DROID_HOOK_CLIENT_PATH" claude-hook userpromptsubmit
"$DROID_HOOK_CLIENT_PATH" claude-hook stop
"$DROID_HOOK_CLIENT_PATH" claude-hook notification
"$DROID_HOOK_CLIENT_PATH" claude-hook permissionrequest
```

Codex activity hooks use:

```bash
"$DROID_HOOK_CLIENT_PATH" codex-activity codex start
"$DROID_HOOK_CLIENT_PATH" codex-activity codex stop
```

OpenCode's plugin calls the same helper with `send` for activity, transcript, and completion events. New coding-agent modules should either install native hooks through their `CodingAgentModule` or call `send`/`codex-activity` directly from their own integration script.

## Delivery Settings

Droid respects the user's choices under **Settings -> Notifications**:

- **Toast** shows an in-app banner.
- **Sound** plays the selected notification sound.
- **Position** controls toast placement.
- **Destinations** can forward normalized events to `ntfy` or custom HTTP webhooks.
- **Rules** match by source and event type before fan-out.

Notifications targeting the currently focused pane still show toast and sound, but they do not create an unread badge for that active tab.
