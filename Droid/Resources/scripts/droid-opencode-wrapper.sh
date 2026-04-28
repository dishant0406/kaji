#!/usr/bin/env bash
set -euo pipefail

find_real_opencode() {
    local self_dir
    self_dir="$(cd "$(dirname "$0")" && pwd)"
    local IFS=:
    for d in $PATH; do
        [[ "$d" == "$self_dir" ]] && continue
        [[ -x "$d/opencode" ]] && printf '%s' "$d/opencode" && return 0
    done
    return 1
}

REAL_OPENCODE="$(find_real_opencode)" || { echo "Error: opencode not found in PATH" >&2; exit 127; }
HELPER_SCRIPT="$(cd "$(dirname "$0")" && pwd)/droid-ai-activity.sh"

if [ -n "${DROID_SOCKET_PATH:-}" ] && [ -n "${DROID_PANE_ID:-}" ]; then
    "$HELPER_SCRIPT" opencode start || true
fi

"$REAL_OPENCODE" "$@"
status=$?

if [ -n "${DROID_SOCKET_PATH:-}" ] && [ -n "${DROID_PANE_ID:-}" ]; then
    "$HELPER_SCRIPT" opencode stop || true
fi

exit $status
