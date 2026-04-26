#!/usr/bin/env bash
set -euo pipefail

if [ -z "${DROID_SOCKET_PATH:-}" ] || [ -z "${DROID_PANE_ID:-}" ]; then
    exit 0
fi

payload="${1:-}"
body="Turn completed"

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
printf 'codex|%s|Codex|%s' "$DROID_PANE_ID" "$body" | nc -U "$DROID_SOCKET_PATH" 2>/dev/null || true
