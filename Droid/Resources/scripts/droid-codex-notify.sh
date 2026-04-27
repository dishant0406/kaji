#!/usr/bin/env bash
set -euo pipefail

socket_path="${DROID_SOCKET_PATH:-${DROID_APP_SUPPORT_DIR:-$HOME/Library/Application Support/Droid}/droid.sock}"
pane_id="${DROID_PANE_ID:-}"

passthrough_count=0
if [ "${1:-}" = "--passthrough-count" ]; then
    passthrough_count="${2:-0}"
    shift 2
fi

passthrough=()
if [ "$passthrough_count" -gt 0 ]; then
    while [ "$passthrough_count" -gt 0 ] && [ "$#" -gt 0 ]; do
        passthrough+=("$1")
        shift
        passthrough_count=$((passthrough_count - 1))
    done
fi

payload="${1:-}"
body="Turn completed"

send_socket_message() {
    /usr/bin/python3 - "$1" "$2" <<'PY'
import socket
import sys

path = sys.argv[1]
payload = sys.argv[2].encode("utf-8")

try:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.connect(path)
        sock.sendall(payload)
except Exception:
    pass
PY
}

if [ -n "$payload" ]; then
    parsed=$(
        /usr/bin/python3 - "$payload" <<'PY'
import json
import sys

try:
    payload = json.loads(sys.argv[1])
except Exception:
    print("")
    raise SystemExit(0)

event_type = str(payload.get("type") or "").strip()
client = str(payload.get("client") or "").strip()

if event_type == "agent-turn-complete":
    message = "Turn completed"
elif event_type:
    message = event_type.replace("-", " ").strip().title()
else:
    message = "Turn completed"

if client:
    message = f"{message} ({client})"

print(message)
PY
    )

    if [ -n "$parsed" ]; then
        body="$parsed"
    fi
fi

body=$(printf '%s' "$body" | tr '\n\r|' '   ' | cut -c1-200)
if [ -S "$socket_path" ]; then
    send_socket_message "$socket_path" "codex|$pane_id|Codex|$body"
fi

if [ "${#passthrough[@]}" -gt 0 ]; then
    "${passthrough[@]}" "$payload" >/dev/null 2>&1 || true
fi
