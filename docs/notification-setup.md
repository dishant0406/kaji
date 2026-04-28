# Notification Setup

Droid already ships built-in integrations for **Codex**, **Claude Code**, and **OpenCode** — toggle them under **Settings → Notifications** and you're done.

This document is for everything else: sending notifications into Droid from **any other tool** (a custom CLI, a shell command, a build script, a different AI agent, etc.).

## How Droid Receives Notifications

Droid listens on a Unix domain socket:

```
~/Library/Application Support/Droid/droid.sock
```

The socket path is also exported to every terminal Droid spawns as the environment variable `DROID_SOCKET_PATH`, along with a per-pane identifier `DROID_PANE_ID`. Any process running inside a Droid terminal pane can read these and send a message.

When a built-in provider such as Codex runs outside a Droid pane, Droid can still receive the notification by connecting to the default socket path directly and leaving `paneID` empty. In that case the notification is routed to the currently active pane.

## Wire Format

One message per connection. The payload is a single UTF-8 line with four pipe-separated fields:

```
<type>|<paneID>|<title>|<body>
```

| Field    | Required | Description                                                                 |
| -------- | -------- | --------------------------------------------------------------------------- |
| `type`   | yes      | Identifier for the source. Unknown values are accepted and shown generically. Built-in values: `claude_hook`, `opencode`. |
| `paneID` | yes      | The pane the event belongs to. Use `$DROID_PANE_ID` when sending from inside a Droid terminal. Leave empty to attach the notification to the currently active pane. |
| `title`  | yes      | Shown as the notification title. If empty, Droid uses `Task completed!`.     |
| `body`   | no       | Notification body. Must not contain `\|` or newlines — replace them first.   |

Constraints:

- Max message size: **64 KB**.
- The `|` character is the field separator — strip or replace it in user-supplied strings.
- Newlines terminate a message; you can send multiple messages on one connection by separating them with `\n`.

## Minimal Example — Shell

From anywhere inside a Droid terminal pane:

```bash
python3 - <<'PY'
import os, socket

path = os.environ["DROID_SOCKET_PATH"]
pane = os.environ["DROID_PANE_ID"]
payload = f"custom|{pane}|Build finished|All tests passed".encode("utf-8")

with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
    s.connect(path)
    s.sendall(payload)
PY
```

Wrap it in a function and call it from anywhere:

```bash
droid_notify() {
    [ -z "${DROID_SOCKET_PATH:-}" ] && return 0
    local title="${1:-Done}"
    local body="${2:-}"
    local safe_body
    safe_body=$(printf '%s' "$body" | tr '|\n\r' '   ' | head -c 500)
    /usr/bin/python3 - "$DROID_SOCKET_PATH" "${DROID_PANE_ID:-}" "$title" "$safe_body" <<'PY'
import socket
import sys

path, pane, title, body = sys.argv[1:5]
payload = f"custom|{pane}|{title}|{body}".encode("utf-8")

try:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(path)
        s.sendall(payload)
except Exception:
    pass
PY
}

# Usage
long-running-build && droid_notify "Build finished" "main @ $(git rev-parse --short HEAD)"
```

## Minimal Example — Node.js

```javascript
import { createConnection } from "net"

function droidNotify(title, body = "") {
  const socketPath = process.env.DROID_SOCKET_PATH
  const paneID = process.env.DROID_PANE_ID || ""
  if (!socketPath) return
  const safeBody = String(body).replace(/[\n\r|]+/g, " ").slice(0, 500)
  const payload = `custom|${paneID}|${title}|${safeBody}`
  const conn = createConnection({ path: socketPath })
  conn.on("error", () => {})
  conn.write(payload, () => conn.end())
}
```

## Minimal Example — Python

```python
import os, socket

def droid_notify(title: str, body: str = "") -> None:
    path = os.environ.get("DROID_SOCKET_PATH")
    pane = os.environ.get("DROID_PANE_ID", "")
    if not path:
        return
    safe_body = body.replace("|", " ").replace("\n", " ")[:500]
    payload = f"custom|{pane}|{title}|{safe_body}".encode("utf-8")
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(path)
        s.sendall(payload)
```

## Reference Implementations

The built-in integrations are good templates for writing your own:

- **Shell hook (Claude Code):** [`scripts/droid-claude-hook.sh`](../scripts/droid-claude-hook.sh)
- **Node plugin (OpenCode):** [`scripts/opencode-droid-plugin.js`](../scripts/opencode-droid-plugin.js)

## Tips

- **Fire and forget.** If Droid isn't running or the socket doesn't exist, the connection will fail — swallow the error rather than crashing your tool. Every example above does this.
- **Don't block.** Open the connection, write the payload, close it. Do not wait for a response — Droid doesn't send one.
- **Sanitize.** Always strip `|`, `\n`, `\r` from user/model-generated content before sending, and cap the body length (200–500 characters is plenty).
- **Pane routing.** If you send from outside a Droid pane (e.g. a cron job), omit `paneID`; Droid will route to the currently active pane of the active project.
- **Type strings.** Pick something descriptive for `type`. If it doesn't match a registered provider, Droid still shows the notification with a generic source — your `title` field is what users actually see.

## Delivery Settings

Regardless of where a notification comes from, Droid respects the user's choices under **Settings → Notifications**:

- **Toast** — show an in-app banner
- **Sound** — play a system sound on arrival, with optional per-rule overrides
- **Position** — where the toast appears

A dot also appears on the project and worktree rows in the sidebar until the notification is read.

If the notification targets the pane you're already looking at, Droid still shows the toast and sound but skips creating a new unread badge for that same focused tab.

Settings also support outbound delivery rules:

- **Destinations** — send normalized notification events to `ntfy` or any custom HTTP webhook
- **Rules** — match by source and event type, then fan out to one or more destinations
- **Templates** — use tokens like `{{title}}`, `{{body}}`, `{{source}}`, `{{event_kind}}`, `{{project}}`, `{{worktree}}`, and `{{timestamp_iso}}`
