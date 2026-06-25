#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
RUN_IN_PLACE="${RUN_IN_PLACE:-1}"
DEFAULT_APP_NAME="Kaji"
DEFAULT_BUNDLE_ID="com.kaji.app"
if [[ "$RUN_IN_PLACE" == "1" ]]; then
  DEFAULT_BUNDLE_ID="com.kaji.dev"
fi
APP_NAME="${APP_NAME_OVERRIDE:-$DEFAULT_APP_NAME}"
BUILD_PRODUCT_NAME="${BUILD_PRODUCT_NAME_OVERRIDE:-Kaji}"
APP_EXECUTABLE_NAME="${APP_EXECUTABLE_NAME_OVERRIDE:-Kaji}"
BUNDLE_ID="${BUNDLE_ID_OVERRIDE:-$DEFAULT_BUNDLE_ID}"
MIN_SYSTEM_VERSION="${MIN_SYSTEM_VERSION_OVERRIDE:-14.0}"
APP_SUPPORT_DIR_OVERRIDE="${APP_SUPPORT_DIR_OVERRIDE:-}"
KILL_BEFORE_LAUNCH="${KILL_BEFORE_LAUNCH:-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INSTALL_APP_BUNDLE="${INSTALL_APP_BUNDLE_OVERRIDE:-/Applications/${APP_NAME}.app}"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_EXECUTABLE_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
PKGINFO="$APP_CONTENTS/PkgInfo"

stop_existing_app() {
  if [[ "$KILL_BEFORE_LAUNCH" != "1" ]]; then
    return
  fi

  local target_binary
  if [[ "$RUN_IN_PLACE" == "1" ]]; then
    target_binary="$APP_BINARY"
  else
    target_binary="$INSTALL_APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE_NAME"
  fi

  pgrep -f "$target_binary" | xargs kill >/dev/null 2>&1 || true
}

clean_spm_resource_bundles() {
  find "$ROOT_DIR/.build" -type d -name "${BUILD_PRODUCT_NAME}_${BUILD_PRODUCT_NAME}.bundle" -prune -exec rm -rf {} + 2>/dev/null || true
}

cd "$ROOT_DIR"
stop_existing_app
clean_spm_resource_bundles
swift build
swift build --target KajiHookClient
BUILD_BIN_DIR="$(swift build --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$BUILD_PRODUCT_NAME"
HOOK_CLIENT_BINARY="$BUILD_BIN_DIR/KajiHookClient"
RESOURCE_BUNDLE_NAME="${BUILD_PRODUCT_NAME}_${BUILD_PRODUCT_NAME}.bundle"
RESOURCE_BUNDLE="$BUILD_BIN_DIR/$RESOURCE_BUNDLE_NAME"
SPARKLE_FRAMEWORK="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
APP_ICONSET_SOURCE="$ROOT_DIR/Kaji/Resources/Assets.xcassets/AppIcon.appiconset"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$HOOK_CLIENT_BINARY" "$APP_MACOS/KajiHookClient"
chmod +x "$APP_MACOS/KajiHookClient"
install_name_tool -add_rpath "@loader_path/../Frameworks" "$APP_BINARY" 2>/dev/null || true

if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/$RESOURCE_BUNDLE_NAME"
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

cp "$ROOT_DIR/Kaji/Info.plist" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_EXECUTABLE_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MIN_SYSTEM_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :NSPrincipalClass NSApplication" "$INFO_PLIST"
printf 'APPL????' >"$PKGINFO"
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

open_app() {
  local open_args=(-n)
  if [[ -n "$APP_SUPPORT_DIR_OVERRIDE" ]]; then
    open_args+=(--env "KAJI_APP_SUPPORT_DIR=$APP_SUPPORT_DIR_OVERRIDE")
  fi

  if [[ "$RUN_IN_PLACE" == "1" ]]; then
    /usr/bin/open "${open_args[@]}" "$APP_BUNDLE"
    return
  fi

  rm -rf "$INSTALL_APP_BUNDLE"
  cp -R "$APP_BUNDLE" "$INSTALL_APP_BUNDLE"
  /usr/bin/open "${open_args[@]}" "$INSTALL_APP_BUNDLE"
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
    /usr/bin/log show --last 5s --info --debug --signpost --style compact --predicate "process == \"$APP_NAME\" && subsystem == \"app.kaji\" && category == \"GhosttyPerf\""
    /usr/bin/log stream --info --debug --signpost --style compact --predicate "process == \"$APP_NAME\" && subsystem == \"app.kaji\" && category == \"GhosttyPerf\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    if [[ "$RUN_IN_PLACE" == "1" ]]; then
      pgrep -f "$APP_BINARY" >/dev/null
    else
      pgrep -f "$INSTALL_APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE_NAME" >/dev/null
    fi
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
