#!/bin/bash
set -euo pipefail

APP_BUNDLE=""
LAUNCH=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --launch)
            LAUNCH=true
            shift
            ;;
        *)
            APP_BUNDLE="$1"
            shift
            ;;
    esac
done

fail() {
    echo "Error: $1" >&2
    exit 1
}

[[ -n "$APP_BUNDLE" ]] || fail "app bundle path is required"
[[ -d "$APP_BUNDLE" ]] || fail "app bundle not found at $APP_BUNDLE"

EXECUTABLE="$APP_BUNDLE/Contents/MacOS/Kaji"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"

[[ -x "$EXECUTABLE" ]] || fail "Kaji executable missing"
plutil -lint "$INFO_PLIST" >/dev/null

RESOURCE_BUNDLE=$(find "$APP_BUNDLE/Contents/Resources" -maxdepth 1 -type d -name "*_Kaji.bundle" -print -quit)
if [[ -z "$RESOURCE_BUNDLE" ]]; then
    RESOURCE_BUNDLE=$(find "$APP_BUNDLE/Contents/Resources" -maxdepth 1 -type d -name "Kaji_Kaji.bundle" -print -quit)
fi
[[ -n "$RESOURCE_BUNDLE" ]] || fail "Kaji resource bundle missing"
RUNTIME_FILE=""
for candidate in \
    "$RESOURCE_BUNDLE/kaji-agent-runtime.mjs" \
    "$RESOURCE_BUNDLE/KajiAgentRuntime/kaji-agent-runtime.mjs"; do
    if [[ -f "$candidate" ]]; then
        RUNTIME_FILE="$candidate"
        break
    fi
done
[[ -n "$RUNTIME_FILE" ]] || fail "Kaji Agent runtime missing from resource bundle"
RUNTIME_SIZE=$(stat -f%z "$RUNTIME_FILE")
[[ "$RUNTIME_SIZE" -gt 1000000 ]] || fail "Kaji Agent runtime is unexpectedly small"

if otool -L "$EXECUTABLE" | grep -q ".dev-support"; then
    fail "Kaji binary links to .dev-support"
fi

if otool -l "$EXECUTABLE" | grep -q ".dev-support"; then
    fail "Kaji binary has .dev-support load command"
fi

if [[ "$LAUNCH" == true || "${KAJI_RELEASE_SMOKE_LAUNCH:-}" == "1" ]]; then
    open -n "$APP_BUNDLE"
    sleep "${KAJI_RELEASE_SMOKE_SECONDS:-5}"
    PID="$(pgrep -f "$EXECUTABLE" | head -1 || true)"
    [[ -n "$PID" ]] || fail "Kaji did not stay running during smoke launch"
    kill "$PID" >/dev/null 2>&1 || true
fi

echo "Release app smoke checks passed"
