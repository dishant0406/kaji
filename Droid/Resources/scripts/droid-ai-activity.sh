#!/usr/bin/env bash
set -euo pipefail

provider="${1:-}"
state="${2:-}"
input=""

if [ -z "${DROID_SOCKET_PATH:-}" ] || [ -z "${DROID_PANE_ID:-}" ]; then
    exit 0
fi

case "$provider" in
    codex|claude|opencode) ;;
    *) exit 0 ;;
esac

case "$state" in
    start|stop) ;;
    *) exit 0 ;;
esac

if [ "$provider" = "codex" ]; then
    input=$(cat)
    if [ -n "$input" ]; then
        should_skip=$(
            /usr/bin/python3 - "$input" <<'PY'
import json
import sys

try:
    payload = json.loads(sys.argv[1])
except Exception:
    print("0")
    raise SystemExit(0)

print("1" if payload.get("agent_id") or payload.get("agent_type") else "0")
PY
        )
        if [ "$should_skip" = "1" ]; then
            exit 0
        fi
    fi
fi

context=""
if [ -n "${DROID_PROJECT_ID:-}" ] && [ -n "${DROID_WORKTREE_ID:-}" ]; then
    context="${DROID_PROJECT_ID},${DROID_WORKTREE_ID},${DROID_WORKTREE_PATH:-}"
fi

send_socket_message() {
    /usr/bin/python3 - "$DROID_SOCKET_PATH" "$1" <<'PY'
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

send_socket_message "${provider}_activity|${DROID_PANE_ID}|${state}|${context}"

if [ "$provider" = "codex" ] && [ -n "$input" ]; then
    transcript=$(
        /usr/bin/python3 - "$state" "$input" <<'PY'
import json
import sys

state = sys.argv[1]

try:
    payload = json.loads(sys.argv[2])
except Exception:
    raise SystemExit(0)

def walk(value):
    if isinstance(value, dict):
        for key in ["prompt", "user_prompt", "last_assistant_message", "message", "text"]:
            candidate = value.get(key)
            if isinstance(candidate, str) and candidate.strip():
                yield candidate
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)

for candidate in walk(payload):
    text = " ".join(candidate.replace("|", " ").split())
    if text:
        print(text[:500])
        break
PY
    )
    if [ -n "$transcript" ]; then
        kind="update"
        if [ "$state" = "start" ]; then
            kind="user"
        fi
        send_socket_message "${provider}_transcript|${DROID_PANE_ID}|${kind}|${transcript}"
    fi
fi
