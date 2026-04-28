#!/usr/bin/env bash
set -euo pipefail

if [ -z "${DROID_SOCKET_PATH:-}" ] || [ -z "${DROID_PANE_ID:-}" ]; then
    exit 0
fi

event="${1:-}"
input=$(cat)

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

send_notification() {
    local type="$1"
    local title="$2"
    local body="$3"
    send_socket_message "$DROID_SOCKET_PATH" "$type|$DROID_PANE_ID|$title|$body"
}

send_activity() {
    local state="$1"
    send_socket_message "$DROID_SOCKET_PATH" "claude_activity|$DROID_PANE_ID|$state|"
}

extract_last_message() {
    local msg=""
    msg=$(printf '%s' "$input" | grep -o '"last_assistant_message":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$msg" ]; then
        printf '%s' "$msg" | tr '|' ' ' | head -c 200
        return
    fi
    printf 'Session completed'
}

case "$event" in
    userpromptsubmit)
        send_activity "start"
        ;;
    permissionrequest)
        send_activity "stop"
        send_notification "claude_hook" "Claude Code" "Needs permission"
        ;;
    notification)
        send_activity "stop"
        send_notification "claude_hook" "Claude Code" "Needs attention"
        ;;
    stop)
        send_activity "stop"
        body=$(extract_last_message)
        send_notification "claude_hook" "Claude Code" "$body"
        ;;
esac
