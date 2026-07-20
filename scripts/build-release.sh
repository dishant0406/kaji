#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
ARCH=""
VERSION=""
SIGN_IDENTITY=""
SPARKLE_PUBLIC_KEY=""
SPARKLE_FEED_URL=""
SMOKE_LAUNCH=false
SKIP_NATIVE_DEPS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --sign-identity)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        --sparkle-public-key)
            SPARKLE_PUBLIC_KEY="$2"
            shift 2
            ;;
        --sparkle-feed-url)
            SPARKLE_FEED_URL="$2"
            shift 2
            ;;
        --smoke-launch)
            SMOKE_LAUNCH=true
            shift
            ;;
        --skip-native-deps)
            SKIP_NATIVE_DEPS=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$ARCH" || -z "$VERSION" ]]; then
    echo "Usage: $0 --arch <arm64|x86_64> --version <X.Y.Z> [--sign-identity <identity>] [--sparkle-public-key <key>] [--sparkle-feed-url <url>] [--smoke-launch]"
    exit 1
fi
if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
    echo "Error: arch must be arm64 or x86_64"
    exit 1
fi
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: version must be in X.Y.Z format"
    exit 1
fi
TRIPLE="${ARCH}-apple-macosx14.0"
BUILD_NUMBER=$(git -C "$PROJECT_ROOT" rev-list --count HEAD)
APP_BUNDLE="$BUILD_DIR/Kaji.app"
DMG_NAME="Kaji-${VERSION}-${ARCH}.dmg"
SIGNING_IDENTITY="${SIGN_IDENTITY:--}"
TERMY_DYLIB="$PROJECT_ROOT/TermyKit/lib/libtermy_ffi.dylib"
RIFT_BINARY="$PROJECT_ROOT/Kaji/Resources/Rift/rift"
sign_code() {
    /usr/bin/codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$@"
}
sign_code_with_entitlements() {
    /usr/bin/codesign --force --options runtime --entitlements "$PROJECT_ROOT/Kaji/Kaji.entitlements" --sign "$SIGNING_IDENTITY" "$@"
}
sign_sparkle() {
    local sparkle_dir="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
    echo "==> Signing Sparkle.framework"
    sign_code --preserve-metadata=entitlements "$sparkle_dir/Versions/B/XPCServices/Installer.xpc"
    sign_code --preserve-metadata=entitlements "$sparkle_dir/Versions/B/XPCServices/Downloader.xpc"
    sign_code --preserve-metadata=entitlements "$sparkle_dir/Versions/B/Updater.app"
    sign_code --preserve-metadata=entitlements "$sparkle_dir/Versions/B/Autoupdate"
    sign_code "$sparkle_dir"
}

rm -rf "$APP_BUNDLE"
echo "==> Building for $ARCH ($TRIPLE)"
cd "$PROJECT_ROOT"
if [[ "${KAJI_SKIP_IGNORE_CATALOG_UPDATE:-0}" != "1" ]]; then
    "$SCRIPT_DIR/update-ignore-catalog.py"
fi
if $SKIP_NATIVE_DEPS; then
    [[ -f "$PROJECT_ROOT/Kaji/Resources/KajiAgentRuntime/kaji-agent-runtime.mjs" ]] || { echo "Error: Kaji runtime is missing; run scripts/build-kaji-agent-runtime.sh" >&2; exit 1; }
    [[ -f "$PROJECT_ROOT/Kaji/Resources/pi/kaji-agent.mjs" ]] || { echo "Error: Parent agent runtime is missing; run scripts/build-parent-agent.sh" >&2; exit 1; }
    [[ -f "$PROJECT_ROOT/Kaji/Resources/pi/oauth-login.mjs" ]] || { echo "Error: Parent agent OAuth runtime is missing; run scripts/build-parent-agent.sh" >&2; exit 1; }
    [[ -f "$PROJECT_ROOT/Kaji/Resources/Zlob/zlob" ]] || { echo "Error: Zlob runtime is missing; run scripts/build-zlob.sh" >&2; exit 1; }
    [[ -f "$PROJECT_ROOT/Kaji/Resources/MonacoEditor/index.html" ]] || { echo "Error: Monaco editor runtime is missing; run scripts/build-monaco-runtime.sh" >&2; exit 1; }
    [[ -f "$TERMY_DYLIB" ]] || { echo "Error: libtermy is missing; run scripts/setup.sh" >&2; exit 1; }
    [[ -x "$RIFT_BINARY" ]] || { echo "Error: Rift runtime is missing; run scripts/build-rift.sh" >&2; exit 1; }
fi
rm -rf "$PROJECT_ROOT/.build/$TRIPLE/release/Kaji_Kaji.bundle"
if ! $SKIP_NATIVE_DEPS; then
    "$SCRIPT_DIR/build-parent-agent.sh"
    "$SCRIPT_DIR/build-kaji-agent-runtime.sh"
    "$SCRIPT_DIR/build-rift.sh"
    "$SCRIPT_DIR/build-zlob.sh"
    "$SCRIPT_DIR/build-monaco-runtime.sh"
fi
swift build -c release --triple "$TRIPLE"
swift build -c release --triple "$TRIPLE" --target KajiHookClient
swift build -c release --triple "$TRIPLE" --product KajiFFFWorker
swift build -c release --triple "$TRIPLE" --product KajiPowerHelper
swift build -c release --triple "$TRIPLE" --product KajiClosedLidGuard
SPM_BUILD_DIR=$(swift build -c release --triple "$TRIPLE" --show-bin-path)
echo "==> Creating app bundle"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$SPM_BUILD_DIR/Kaji" "$APP_BUNDLE/Contents/MacOS/Kaji"
cp "$SPM_BUILD_DIR/KajiHookClient" "$APP_BUNDLE/Contents/MacOS/KajiHookClient"
cp "$SPM_BUILD_DIR/KajiFFFWorker" "$APP_BUNDLE/Contents/MacOS/KajiFFFWorker"
cp "$SPM_BUILD_DIR/KajiPowerHelper" "$APP_BUNDLE/Contents/MacOS/KajiPowerHelper"
cp "$SPM_BUILD_DIR/KajiClosedLidGuard" "$APP_BUNDLE/Contents/MacOS/KajiClosedLidGuard"
echo "==> Stripping local and debug symbols"
strip -Sx "$APP_BUNDLE/Contents/MacOS/Kaji"
strip -Sx "$APP_BUNDLE/Contents/MacOS/KajiHookClient"
strip -Sx "$APP_BUNDLE/Contents/MacOS/KajiFFFWorker"
strip -Sx "$APP_BUNDLE/Contents/MacOS/KajiPowerHelper"
strip -Sx "$APP_BUNDLE/Contents/MacOS/KajiClosedLidGuard"
RESOURCE_BUNDLE_NAME="Kaji_Kaji.bundle"
RESOURCE_BUNDLE_SOURCE="$SPM_BUILD_DIR/$RESOURCE_BUNDLE_NAME"
if [[ ! -d "$RESOURCE_BUNDLE_SOURCE" ]]; then
    echo "Error: Kaji resource bundle not found at $RESOURCE_BUNDLE_SOURCE"
    exit 1
fi
cp -R "$RESOURCE_BUNDLE_SOURCE" "$APP_BUNDLE/Contents/Resources/$RESOURCE_BUNDLE_NAME"
"$SCRIPT_DIR/stage-kaji-agent-native-addon.sh" --arch "$ARCH" --destination "$APP_BUNDLE/Contents/Resources/native"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
cp "$PROJECT_ROOT/Kaji/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
mkdir -p "$APP_BUNDLE/Contents/Library/LaunchDaemons"
cp "$PROJECT_ROOT/KajiPowerHelper/com.kaji.app.power-helper.plist" "$APP_BUNDLE/Contents/Library/LaunchDaemons/com.kaji.app.power-helper.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"
echo "==> Generating app icon"
"$SCRIPT_DIR/create-icns.sh" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
echo "==> Embedding Sparkle.framework"
SPARKLE_FRAMEWORK="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
    echo "Error: Sparkle.framework not found at $SPARKLE_FRAMEWORK"
    exit 1
fi
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
cp -R "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
if ! otool -l "$APP_BUNDLE/Contents/MacOS/Kaji" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/Kaji"
fi
if otool -l "$APP_BUNDLE/Contents/MacOS/Kaji" | grep -q "$PROJECT_ROOT/TermyKit/lib"; then
    install_name_tool -delete_rpath "$PROJECT_ROOT/TermyKit/lib" "$APP_BUNDLE/Contents/MacOS/Kaji"
fi
echo "==> Embedding libtermy"
cp "$TERMY_DYLIB" "$APP_BUNDLE/Contents/Frameworks/libtermy_ffi.dylib"
if [[ -n "$SPARKLE_PUBLIC_KEY" ]]; then
    echo "==> Injecting Sparkle keys into Info.plist"
    APP_PLIST="$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY" "$APP_PLIST"
    if [[ -n "$SPARKLE_FEED_URL" ]]; then
        /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$APP_PLIST"
    fi
fi
sign_sparkle
echo "==> Signing Kaji runtime native addon"
for addon in "$APP_BUNDLE"/Contents/Resources/native/*.node; do
    [[ -f "$addon" ]] || continue
    sign_code "$addon"
done
echo "==> Signing KajiPowerHelper"
/usr/bin/codesign --force --options runtime --entitlements "$PROJECT_ROOT/KajiPowerHelper/KajiPowerHelper.entitlements" --sign "$SIGNING_IDENTITY" "$APP_BUNDLE/Contents/MacOS/KajiPowerHelper"
echo "==> Signing KajiClosedLidGuard"
sign_code "$APP_BUNDLE/Contents/MacOS/KajiClosedLidGuard"
echo "==> Signing KajiHookClient"
sign_code "$APP_BUNDLE/Contents/MacOS/KajiHookClient"
echo "==> Signing KajiFFFWorker"
/usr/bin/codesign --force --options runtime --entitlements "$PROJECT_ROOT/KajiFFFWorker/KajiFFFWorker.entitlements" --sign "$SIGNING_IDENTITY" "$APP_BUNDLE/Contents/MacOS/KajiFFFWorker"
echo "==> Signing libtermy"
sign_code "$APP_BUNDLE/Contents/Frameworks/libtermy_ffi.dylib"
echo "==> Signing app bundle"
sign_code_with_entitlements "$APP_BUNDLE"
SMOKE_ARGS=("$APP_BUNDLE")
if [[ "$SMOKE_LAUNCH" == true ]]; then
    SMOKE_ARGS+=(--launch)
fi
echo "==> Running release smoke checks"
"$SCRIPT_DIR/smoke-release-app.sh" "${SMOKE_ARGS[@]}"
echo "==> Creating DMG"
if ! command -v create-dmg &> /dev/null; then
    echo "Error: create-dmg not found. Install with: npm install --global create-dmg"
    exit 1
fi
cd "$BUILD_DIR"
find "$BUILD_DIR" -maxdepth 1 -name "Kaji*.dmg" -delete
create-dmg "$APP_BUNDLE" "$BUILD_DIR" || true
GENERATED_DMG=$(find "$BUILD_DIR" -maxdepth 1 -name "Kaji*.dmg" -not -name "$DMG_NAME" -print0 | xargs -0 ls -t | head -1)
if [[ -n "$GENERATED_DMG" ]]; then
    mv "$GENERATED_DMG" "$BUILD_DIR/$DMG_NAME"
fi
if [[ -n "$SIGN_IDENTITY" && -f "$BUILD_DIR/$DMG_NAME" ]]; then
    echo "==> Signing DMG"
    /usr/bin/codesign --force --sign "$SIGN_IDENTITY" "$BUILD_DIR/$DMG_NAME"
fi
echo "==> Done: $BUILD_DIR/$DMG_NAME"
