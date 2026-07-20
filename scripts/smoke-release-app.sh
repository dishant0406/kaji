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
    [[ -f "$path" ]] || fail "Kaji runtime native addon missing at $path"
    codesign --verify "$path" >/dev/null 2>&1 || fail "Kaji runtime native addon is not signed: $path"
}

[[ -n "$APP_BUNDLE" ]] || fail "app bundle path is required"
[[ -d "$APP_BUNDLE" ]] || fail "app bundle not found at $APP_BUNDLE"
APP_BUNDLE="$(cd "$APP_BUNDLE" && pwd -P)"

EXECUTABLE="$APP_BUNDLE/Contents/MacOS/Kaji"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
FFF_WORKER="$APP_BUNDLE/Contents/MacOS/KajiFFFWorker"
POWER_HELPER="$APP_BUNDLE/Contents/MacOS/KajiPowerHelper"
POWER_HELPER_PLIST="$APP_BUNDLE/Contents/Library/LaunchDaemons/com.kaji.app.power-helper.plist"
CLOSED_LID_GUARD="$APP_BUNDLE/Contents/MacOS/KajiClosedLidGuard"

[[ -x "$EXECUTABLE" ]] || fail "Kaji executable missing"
[[ -x "$FFF_WORKER" ]] || fail "KajiFFFWorker executable missing"
codesign --verify "$FFF_WORKER" >/dev/null 2>&1 || fail "KajiFFFWorker is not signed"
codesign -d --entitlements :- "$FFF_WORKER" 2>/dev/null | grep -q "com.apple.security.cs.disable-library-validation" || fail "KajiFFFWorker cannot load the isolated FFF library"
[[ -x "$POWER_HELPER" ]] || fail "KajiPowerHelper executable missing"
[[ -f "$POWER_HELPER_PLIST" ]] || fail "KajiPowerHelper LaunchDaemon plist missing"
plutil -lint "$POWER_HELPER_PLIST" >/dev/null || fail "KajiPowerHelper LaunchDaemon plist is invalid"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :Label' "$POWER_HELPER_PLIST")" == "com.kaji.app.power-helper" ]] || fail "KajiPowerHelper label is invalid"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :BundleProgram' "$POWER_HELPER_PLIST")" == "Contents/MacOS/KajiPowerHelper" ]] || fail "KajiPowerHelper BundleProgram is invalid"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :MachServices:com.kaji.app.power-helper' "$POWER_HELPER_PLIST")" == "true" ]] || fail "KajiPowerHelper Mach service is invalid"
codesign --verify --strict "$POWER_HELPER" >/dev/null 2>&1 || fail "KajiPowerHelper is not signed"
[[ -x "$CLOSED_LID_GUARD" ]] || fail "KajiClosedLidGuard executable missing"
codesign --verify --strict "$CLOSED_LID_GUARD" >/dev/null 2>&1 || fail "KajiClosedLidGuard is not signed"
APP_TEAM_IDENTIFIER="$(codesign -dv "$EXECUTABLE" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
HELPER_TEAM_IDENTIFIER="$(codesign -dv "$POWER_HELPER" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
if [[ -n "$APP_TEAM_IDENTIFIER" && "$APP_TEAM_IDENTIFIER" != "not set" ]]; then
    [[ "$HELPER_TEAM_IDENTIFIER" == "$APP_TEAM_IDENTIFIER" ]] || fail "KajiPowerHelper signing team does not match Kaji"
fi
if codesign -d --entitlements :- "$POWER_HELPER" 2>&1 | grep -q '<key>'; then
    fail "KajiPowerHelper must not carry privileged entitlements"
fi
if otool -L "$EXECUTABLE" | grep -q "fff"; then
    fail "Kaji executable must not link FFF"
fi
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
[[ -n "$RUNTIME_FILE" ]] || fail "Kaji runtime missing from resource bundle"
RUNTIME_SIZE=$(stat -f%z "$RUNTIME_FILE")
[[ "$RUNTIME_SIZE" -gt 1000000 ]] || fail "Kaji runtime is unexpectedly small"

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
