#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Droid"
BUNDLE_ID="com.droid.app"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INSTALL_APP_BUNDLE="/Applications/${APP_NAME}.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
PKGINFO="$APP_CONTENTS/PkgInfo"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build
BUILD_BIN_DIR="$(swift build --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$APP_NAME"
RESOURCE_BUNDLE="$BUILD_BIN_DIR/${APP_NAME}_${APP_NAME}.bundle"
SPARKLE_FRAMEWORK="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
APP_ICONSET_SOURCE="$ROOT_DIR/Droid/Resources/Assets.xcassets/AppIcon.appiconset"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
install_name_tool -add_rpath "@loader_path/../Frameworks" "$APP_BINARY" 2>/dev/null || true

if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/${APP_NAME}_${APP_NAME}.bundle"
fi

if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
  cp -R "$SPARKLE_FRAMEWORK" "$APP_FRAMEWORKS/Sparkle.framework"
fi

if [[ -d "$APP_ICONSET_SOURCE" ]]; then
  ICONSET_DIR="$(mktemp -d "$ROOT_DIR/.appicon.XXXXXX")"
  mkdir -p "$ICONSET_DIR/AppIcon.iconset"
  cp "$APP_ICONSET_SOURCE/icon_16.png" "$ICONSET_DIR/AppIcon.iconset/icon_16x16.png"
  cp "$APP_ICONSET_SOURCE/icon_16@2x.png" "$ICONSET_DIR/AppIcon.iconset/icon_16x16@2x.png"
  cp "$APP_ICONSET_SOURCE/icon_32.png" "$ICONSET_DIR/AppIcon.iconset/icon_32x32.png"
  cp "$APP_ICONSET_SOURCE/icon_32@2x.png" "$ICONSET_DIR/AppIcon.iconset/icon_32x32@2x.png"
  cp "$APP_ICONSET_SOURCE/icon_128.png" "$ICONSET_DIR/AppIcon.iconset/icon_128x128.png"
  cp "$APP_ICONSET_SOURCE/icon_128@2x.png" "$ICONSET_DIR/AppIcon.iconset/icon_128x128@2x.png"
  cp "$APP_ICONSET_SOURCE/icon_256.png" "$ICONSET_DIR/AppIcon.iconset/icon_256x256.png"
  cp "$APP_ICONSET_SOURCE/icon_256@2x.png" "$ICONSET_DIR/AppIcon.iconset/icon_256x256@2x.png"
  cp "$APP_ICONSET_SOURCE/icon_512.png" "$ICONSET_DIR/AppIcon.iconset/icon_512x512.png"
  cp "$APP_ICONSET_SOURCE/icon_512@2x.png" "$ICONSET_DIR/AppIcon.iconset/icon_512x512@2x.png"
  /usr/bin/iconutil -c icns "$ICONSET_DIR/AppIcon.iconset" -o "$APP_RESOURCES/AppIcon.icns"
  rm -rf "$ICONSET_DIR"
fi

cp "$ROOT_DIR/Droid/Info.plist" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MIN_SYSTEM_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :NSPrincipalClass NSApplication" "$INFO_PLIST"
printf 'APPL????' >"$PKGINFO"
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

open_app() {
  rm -rf "$INSTALL_APP_BUNDLE"
  cp -R "$APP_BUNDLE" "$INSTALL_APP_BUNDLE"
  /usr/bin/open -n "$INSTALL_APP_BUNDLE"
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
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
