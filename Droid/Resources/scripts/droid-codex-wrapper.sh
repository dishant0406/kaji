#!/usr/bin/env bash
set -euo pipefail

find_real_codex() {
    local self_dir
    self_dir="$(cd "$(dirname "$0")" && pwd)"
    local IFS=:
    for d in $PATH; do
        [[ "$d" == "$self_dir" ]] && continue
        [[ -x "$d/codex" ]] && printf '%s' "$d/codex" && return 0
    done
    return 1
}

REAL_CODEX="$(find_real_codex)" || { echo "Error: codex not found in PATH" >&2; exit 127; }
HELPER_SCRIPT="$(cd "$(dirname "$0")" && pwd)/droid-ai-activity.sh"

if [ -n "${DROID_SOCKET_PATH:-}" ] && [ -n "${DROID_PANE_ID:-}" ]; then
    "$HELPER_SCRIPT" codex start || true
fi

"$REAL_CODEX" "$@"
status=$?

if [ -n "${DROID_SOCKET_PATH:-}" ] && [ -n "${DROID_PANE_ID:-}" ]; then
    "$HELPER_SCRIPT" codex stop || true
fi

exit $status
