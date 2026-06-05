#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GHOSTTY_REPO="${GHOSTTY_REPO:-ghostty-org/ghostty}"
GHOSTTY_REF="${GHOSTTY_REF:-d5d8cef4d3834cc8999eb9344066b0960b033f2d}"
GHOSTTY_URL="https://github.com/${GHOSTTY_REPO}.git"
XCFRAMEWORK_DIR="$PROJECT_ROOT/GhosttyKit.xcframework"
HEADER_PATH="$PROJECT_ROOT/GhosttyKit/ghostty.h"
RUNTIME_RESOURCES_DIR="$PROJECT_ROOT/Kaji/Resources/ghostty"
STAMP_FILE="$PROJECT_ROOT/.ghostty-source"
REQUIRED_ZIG_VERSION="${REQUIRED_ZIG_VERSION:-0.15.2}"
GHOSTTY_OPTIMIZE="${GHOSTTY_OPTIMIZE:-ReleaseFast}"
GHOSTTY_CPU="${GHOSTTY_CPU:-baseline}"
EXPECTED_STAMP="repo=${GHOSTTY_REPO}
ref=${GHOSTTY_REF}
zig=${REQUIRED_ZIG_VERSION}
optimize=${GHOSTTY_OPTIMIZE}
cpu=${GHOSTTY_CPU}"

require_tool() {
    local tool="$1"
    local install_hint="$2"
    if command -v "$tool" >/dev/null 2>&1; then
        return
    fi
    echo "Error: $tool is required."
    echo "Install it with: $install_hint"
    exit 1
}

invalidate_swiftpm_ghostty_products() {
    if [[ ! -d "$PROJECT_ROOT/.build" ]]; then
        return
    fi

    find "$PROJECT_ROOT/.build" \
        \( -path "*/debug/Kaji" -o -path "*/release/Kaji" -o -path "*/debug/KajiPackageTests.xctest" -o -path "*/release/KajiPackageTests.xctest" \) \
        -exec rm -rf {} +
    rm -rf "$PROJECT_ROOT/.build/KajiSwiftRun.app"
}

require_tool git "brew install git"

if ! xcode-select --print-path | grep -q "/Applications/Xcode.app/Contents/Developer"; then
    echo "Error: Xcode must be the active developer directory."
    echo "Run: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
    exit 1
fi

if [[ "${GHOSTTY_FORCE_REBUILD:-0}" != "1" ]] \
    && [[ -d "$XCFRAMEWORK_DIR" && -f "$STAMP_FILE" ]] \
    && [[ "$(cat "$STAMP_FILE")" == "$EXPECTED_STAMP" ]] \
    && [[ -d "$RUNTIME_RESOURCES_DIR/shell-integration" ]] \
    && [[ -d "$RUNTIME_RESOURCES_DIR/terminfo" ]]; then
    echo "==> GhosttyKit.xcframework already matches $GHOSTTY_REPO@$GHOSTTY_REF"
    echo "==> Invalidating SwiftPM products that statically link GhosttyKit"
    invalidate_swiftpm_ghostty_products
    exit 0
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

ZIG_BIN="zig"
if ! command -v zig >/dev/null 2>&1 || [[ "$(zig version)" != "$REQUIRED_ZIG_VERSION" ]]; then
    case "$(uname -m)" in
        arm64) ZIG_ARCH="aarch64" ;;
        x86_64) ZIG_ARCH="x86_64" ;;
        *)
            echo "Error: Unsupported macOS architecture $(uname -m)"
            exit 1
            ;;
    esac

    ZIG_DIR="$WORK_DIR/zig"
    mkdir -p "$ZIG_DIR"
    ZIG_ARCHIVE="zig-${ZIG_ARCH}-macos-${REQUIRED_ZIG_VERSION}.tar.xz"
    ZIG_URL="https://ziglang.org/download/${REQUIRED_ZIG_VERSION}/${ZIG_ARCHIVE}"

    echo "==> Using temporary Zig $REQUIRED_ZIG_VERSION"
    curl --fail --location --show-error --retry 5 --retry-delay 5 --retry-all-errors "$ZIG_URL" -o "$ZIG_DIR/$ZIG_ARCHIVE"
    tar -xf "$ZIG_DIR/$ZIG_ARCHIVE" -C "$ZIG_DIR"
    ZIG_BIN="$ZIG_DIR/zig-${ZIG_ARCH}-macos-${REQUIRED_ZIG_VERSION}/zig"
fi

echo "==> Cloning $GHOSTTY_REPO@$GHOSTTY_REF"
if git ls-remote --exit-code --heads "$GHOSTTY_URL" "$GHOSTTY_REF" >/dev/null 2>&1; then
    git clone --depth 1 --branch "$GHOSTTY_REF" "$GHOSTTY_URL" "$WORK_DIR/ghostty"
else
    git clone --depth 1 --no-checkout "$GHOSTTY_URL" "$WORK_DIR/ghostty"
    git -C "$WORK_DIR/ghostty" fetch --depth 1 origin "$GHOSTTY_REF"
    git -C "$WORK_DIR/ghostty" checkout --detach FETCH_HEAD
fi
git -C "$WORK_DIR/ghostty" submodule update --init --recursive --depth 1

echo "==> Building GhosttyKit.xcframework from upstream source"
(
    cd "$WORK_DIR/ghostty"
    "$ZIG_BIN" build \
        -Doptimize="$GHOSTTY_OPTIMIZE" \
        -Dcpu="$GHOSTTY_CPU" \
        -Demit-xcframework=true \
        -Dxcframework-target=universal \
        -Demit-macos-app=false
)

SOURCE_XCFRAMEWORK="$WORK_DIR/ghostty/macos/GhosttyKit.xcframework"
SOURCE_HEADER="$WORK_DIR/ghostty/include/ghostty.h"
SOURCE_RUNTIME_DIR="$WORK_DIR/ghostty/zig-out/share/ghostty"
SOURCE_TERMINFO_DIR="$WORK_DIR/ghostty/zig-out/share/terminfo"

if [[ ! -d "$SOURCE_XCFRAMEWORK" ]]; then
    echo "Error: Expected GhosttyKit.xcframework at $SOURCE_XCFRAMEWORK"
    exit 1
fi

if [[ ! -f "$SOURCE_HEADER" ]]; then
    echo "Error: Expected ghostty.h at $SOURCE_HEADER"
    exit 1
fi

if [[ ! -d "$SOURCE_RUNTIME_DIR/shell-integration" ]]; then
    echo "Error: Expected Ghostty shell integration at $SOURCE_RUNTIME_DIR/shell-integration"
    exit 1
fi

if [[ ! -d "$SOURCE_TERMINFO_DIR" ]]; then
    echo "Error: Expected Ghostty terminfo at $SOURCE_TERMINFO_DIR"
    exit 1
fi

echo "==> Installing GhosttyKit.xcframework"
rm -rf "$XCFRAMEWORK_DIR"
cp -R "$SOURCE_XCFRAMEWORK" "$XCFRAMEWORK_DIR"
cp "$SOURCE_HEADER" "$HEADER_PATH"
rm -rf "$RUNTIME_RESOURCES_DIR"
mkdir -p "$RUNTIME_RESOURCES_DIR"
cp -R "$SOURCE_RUNTIME_DIR/shell-integration" "$RUNTIME_RESOURCES_DIR/shell-integration"
cp -R "$SOURCE_TERMINFO_DIR" "$RUNTIME_RESOURCES_DIR/terminfo"
printf "%s\n" "$EXPECTED_STAMP" > "$STAMP_FILE"
invalidate_swiftpm_ghostty_products


echo "==> Building Kaji Agent runtime"
if command -v bun >/dev/null 2>&1; then
    bash "$SCRIPT_DIR/build-kaji-agent-runtime.sh"
else
    echo "    Bun not found; skipping agent runtime build (install: curl -fsSL https://bun.sh/install | bash)"
fi

echo "==> Done"
echo "    Run 'swift build' to build the project"
