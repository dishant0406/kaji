#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREVIEW_FILE="$ROOT_DIR/Kaji/Previews/DeveloperPreviewLab.swift"
OPEN_XCODE="${START_OPEN_XCODE:-1}"

if [[ ! -d "$ROOT_DIR/GhosttyKit.xcframework" || ! -f "$ROOT_DIR/.ghostty-source" ]]; then
    "$ROOT_DIR/scripts/setup.sh"
fi

swift package resolve

if [[ "$OPEN_XCODE" == "1" ]] && command -v xed >/dev/null 2>&1; then
    xed "$PREVIEW_FILE"
fi

"$ROOT_DIR/script/build_and_run.sh" "$MODE"

if [[ "$OPEN_XCODE" == "1" ]]; then
    cat <<EOF
Xcode opened on $PREVIEW_FILE
Enable the canvas with Editor > Canvas to use live previews while the app runs separately.
EOF
fi
