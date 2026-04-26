#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Droid"
BUNDLE_ID="com.droid.app"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

BUILD_DIR="$(swift build --show-bin-path)"
RESOURCE_BUNDLE="$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle"
rm -rf "$RESOURCE_BUNDLE"

swift build

BUILD_BINARY="$BUILD_DIR/$APP_NAME"
SPARKLE_FRAMEWORK="$BUILD_DIR/Sparkle.framework"

if [[ ! -x "$BUILD_BINARY" ]]; then
    echo "Error: missing built app binary at $BUILD_BINARY" >&2
    exit 1
fi

if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
    echo "Error: missing resource bundle at $RESOURCE_BUNDLE" >&2
    exit 1
fi

if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
    echo "Error: missing Sparkle.framework at $SPARKLE_FRAMEWORK" >&2
    exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
ditto "$RESOURCE_BUNDLE" "$APP_RESOURCES/$(basename "$RESOURCE_BUNDLE")"
ditto "$SPARKLE_FRAMEWORK" "$APP_MACOS/Sparkle.framework"
cp "$ROOT_DIR/Droid/Info.plist" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 1" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.0.0-dev" "$INFO_PLIST"
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null

open_app() {
    /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
    run)
        open_app
        ;;
    --debug|debug)
        lldb -- "$APP_BINARY"
        ;;
    --logs|logs)
        open_app
        /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
        ;;
    --telemetry|telemetry)
        open_app
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"app.droid\""
        ;;
    --verify|verify)
        open_app
        sleep 2
        pgrep -x "$APP_NAME" >/dev/null
        ;;
    *)
        echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
        exit 2
        ;;
esac
