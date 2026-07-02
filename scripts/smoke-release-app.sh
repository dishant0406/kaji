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

require_native_addon() {
    local arch="$1"
    local addon=""
    case "$arch" in
        arm64)
            addon="pi_natives.darwin-arm64.node"
            ;;
        x86_64)
            addon="pi_natives.darwin-x64-baseline.node"
            ;;
        *)
            return
            ;;
    esac

    local path="$APP_BUNDLE/Contents/Resources/native/$addon"
    [[ -f "$path" ]] || fail "Kaji Agent native addon missing at $path"
    codesign --verify "$path" >/dev/null 2>&1 || fail "Kaji Agent native addon is not signed: $path"
}

[[ -n "$APP_BUNDLE" ]] || fail "app bundle path is required"
[[ -d "$APP_BUNDLE" ]] || fail "app bundle not found at $APP_BUNDLE"
APP_BUNDLE="$(cd "$APP_BUNDLE" && pwd -P)"

EXECUTABLE="$APP_BUNDLE/Contents/MacOS/Kaji"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"

[[ -x "$EXECUTABLE" ]] || fail "Kaji executable missing"
plutil -lint "$INFO_PLIST" >/dev/null

ROOT_RESOURCE_BUNDLE="$APP_BUNDLE/Kaji_Kaji.bundle"
RESOURCE_BUNDLE="$APP_BUNDLE/Contents/Resources/Kaji_Kaji.bundle"
[[ ! -e "$ROOT_RESOURCE_BUNDLE" ]] || fail "Kaji resource bundle must not be placed in the app bundle root"
[[ -d "$RESOURCE_BUNDLE" ]] || fail "Kaji resource bundle missing at $RESOURCE_BUNDLE"
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

for arch in $(lipo -archs "$EXECUTABLE"); do
    require_native_addon "$arch"
done

if otool -L "$EXECUTABLE" | grep -q ".dev-support"; then
    fail "Kaji binary links to .dev-support"
fi

if otool -l "$EXECUTABLE" | grep -q ".dev-support"; then
    fail "Kaji binary has .dev-support load command"
fi

if otool -L "$EXECUTABLE" | grep -q "@rpath/libtermy_ffi.dylib"; then
    TERMY_DYLIB="$APP_BUNDLE/Contents/Frameworks/libtermy_ffi.dylib"
    [[ -f "$TERMY_DYLIB" ]] || fail "libtermy missing from app bundle"
    codesign --verify "$TERMY_DYLIB" >/dev/null 2>&1 || fail "libtermy is not signed"
    otool -l "$EXECUTABLE" | grep -q "@executable_path/../Frameworks" || fail "Kaji executable cannot resolve bundled libtermy"
fi

if otool -l "$EXECUTABLE" | grep -q "TermyKit/lib"; then
    fail "Kaji binary has source-tree TermyKit rpath"
fi

if otool -L "$EXECUTABLE" | grep -q "@rpath/Sparkle.framework"; then
    [[ -d "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework" ]] || fail "Sparkle.framework missing from app bundle"
    otool -l "$EXECUTABLE" | grep -q "@executable_path/../Frameworks" || fail "Kaji executable cannot resolve bundled frameworks"
fi

if [[ "$LAUNCH" == true || "${KAJI_RELEASE_SMOKE_LAUNCH:-}" == "1" ]]; then
    open -n "$APP_BUNDLE"
    sleep "${KAJI_RELEASE_SMOKE_SECONDS:-5}"
    PID=""
    while read -r candidate; do
        [[ -n "$candidate" ]] || continue
        [[ "$(ps -p "$candidate" -o comm= 2>/dev/null | xargs)" == "$EXECUTABLE" ]] || continue
        PID="$candidate"
        break
    done < <(pgrep -x "$(basename "$EXECUTABLE")" || true)
    [[ -n "$PID" ]] || fail "Kaji did not stay running during smoke launch"
    kill "$PID" >/dev/null 2>&1 || true
fi

echo "Release app smoke checks passed"
