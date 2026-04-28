#!/usr/bin/env bash
set -euo pipefail

provider="${1:-}"
state="${2:-}"

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

/usr/bin/python3 - "$DROID_SOCKET_PATH" "${provider}_activity|${DROID_PANE_ID}|${state}|" <<'PY'
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
