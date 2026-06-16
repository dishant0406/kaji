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
CEF_ROOT="$PROJECT_ROOT/.dev-support/cef-runtime/cef_binary"
CEF_BUILD="$PROJECT_ROOT/.dev-support/cef-runtime/build/tests/cefsimple/Release"
SIGNING_IDENTITY="${SIGN_IDENTITY:--}"

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

sign_cef_runtime() {
    local framework_dir="$APP_BUNDLE/Contents/Frameworks/Chromium Embedded Framework.framework"

    echo "==> Signing CEF runtime"
    for library in "$framework_dir"/Libraries/*.dylib; do
        [[ -f "$library" ]] || continue
        sign_code "$library"
    done
    sign_code "$framework_dir"

    for helper in "$APP_BUNDLE"/Contents/Frameworks/cefsimple\ Helper*.app; do
        [[ -d "$helper" ]] || continue
        sign_code_with_entitlements "$helper"
    done
}

rm -rf "$APP_BUNDLE"


echo "==> Building for $ARCH ($TRIPLE)"
cd "$PROJECT_ROOT"
if $SKIP_NATIVE_DEPS; then
    [[ -f "$PROJECT_ROOT/Kaji/Resources/KajiAgentRuntime/kaji-agent-runtime.mjs" ]] || { echo "Error: Kaji Agent runtime is missing; run scripts/build-kaji-agent-runtime.sh" >&2; exit 1; }
    [[ -f "$PROJECT_ROOT/Kaji/Resources/pi/kaji-agent.mjs" ]] || { echo "Error: Parent agent runtime is missing; run scripts/build-parent-agent.sh" >&2; exit 1; }
    [[ -f "$PROJECT_ROOT/Kaji/Resources/pi/oauth-login.mjs" ]] || { echo "Error: Parent agent OAuth runtime is missing; run scripts/build-parent-agent.sh" >&2; exit 1; }
    [[ -f "$PROJECT_ROOT/Kaji/Resources/Zlob/zlob" ]] || { echo "Error: Zlob runtime is missing; run scripts/build-zlob.sh" >&2; exit 1; }
    [[ -f "$PROJECT_ROOT/Kaji/Resources/MonacoEditor/index.html" ]] || { echo "Error: Monaco editor runtime is missing; run scripts/build-monaco-runtime.sh" >&2; exit 1; }
fi
rm -rf "$PROJECT_ROOT/.build/$TRIPLE/release/Kaji_Kaji.bundle"
if ! $SKIP_NATIVE_DEPS; then
    "$SCRIPT_DIR/install-cef-runtime.sh" --arch "$ARCH"
    "$SCRIPT_DIR/build-parent-agent.sh"
    "$SCRIPT_DIR/build-kaji-agent-runtime.sh"
    "$SCRIPT_DIR/build-zlob.sh"
    "$SCRIPT_DIR/build-monaco-runtime.sh"
fi
swift build -c release --triple "$TRIPLE"
swift build -c release --triple "$TRIPLE" --target KajiHookClient

SPM_BUILD_DIR=$(swift build -c release --triple "$TRIPLE" --show-bin-path)

echo "==> Creating app bundle"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$SPM_BUILD_DIR/Kaji" "$APP_BUNDLE/Contents/MacOS/Kaji"
cp "$SPM_BUILD_DIR/KajiHookClient" "$APP_BUNDLE/Contents/MacOS/KajiHookClient"
otool -l "$APP_BUNDLE/Contents/MacOS/Kaji" | grep -Fq "path @executable_path/../Frameworks" || install_name_tool -add_rpath @executable_path/../Frameworks "$APP_BUNDLE/Contents/MacOS/Kaji"
install_name_tool -delete_rpath "$CEF_ROOT/Release" "$APP_BUNDLE/Contents/MacOS/Kaji" 2>/dev/null || true

echo "==> Stripping local and debug symbols"
strip -Sx "$APP_BUNDLE/Contents/MacOS/Kaji"
strip -Sx "$APP_BUNDLE/Contents/MacOS/KajiHookClient"

if [[ -d "$SPM_BUILD_DIR/Kaji_Kaji.bundle" ]]; then
    cp -R "$SPM_BUILD_DIR/Kaji_Kaji.bundle" "$APP_BUNDLE/Contents/Resources/Kaji_Kaji.bundle"
fi
"$SCRIPT_DIR/stage-kaji-agent-native-addon.sh" --arch "$ARCH" --destination "$APP_BUNDLE/Contents/Resources/native"

mkdir -p "$APP_BUNDLE/Contents/Frameworks"
if [[ -d "$CEF_ROOT/Release/Chromium Embedded Framework.framework" ]]; then
    cp -R "$CEF_ROOT/Release/Chromium Embedded Framework.framework" "$APP_BUNDLE/Contents/Frameworks/Chromium Embedded Framework.framework"
fi
for helper in "$CEF_BUILD"/cefsimple\ Helper*.app; do
    [[ -d "$helper" ]] || continue
    cp -R "$helper" "$APP_BUNDLE/Contents/Frameworks/$(basename "$helper")"
done

cp "$PROJECT_ROOT/Kaji/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
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

if [[ -n "$SPARKLE_PUBLIC_KEY" ]]; then
    echo "==> Injecting Sparkle keys into Info.plist"
    APP_PLIST="$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY" "$APP_PLIST"
    if [[ -n "$SPARKLE_FEED_URL" ]]; then
        /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$APP_PLIST"
    fi
fi

sign_sparkle
sign_cef_runtime

echo "==> Signing Kaji Agent native addon"
for addon in "$APP_BUNDLE"/Contents/Resources/native/*.node; do
    [[ -f "$addon" ]] || continue
    sign_code "$addon"
done

echo "==> Signing KajiHookClient"
sign_code "$APP_BUNDLE/Contents/MacOS/KajiHookClient"

echo "==> Signing app bundle"
sign_code_with_entitlements "$APP_BUNDLE"


echo "==> Validating bundled CEF runtime"
"$SCRIPT_DIR/validate-cef-bundle.sh" "$APP_BUNDLE" "$ARCH"

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
