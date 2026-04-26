#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GHOSTTY_REPO="${GHOSTTY_REPO:-ghostty-org/ghostty}"
GHOSTTY_REF="${GHOSTTY_REF:-main}"
GHOSTTY_URL="https://github.com/${GHOSTTY_REPO}.git"
XCFRAMEWORK_DIR="$PROJECT_ROOT/GhosttyKit.xcframework"
HEADER_PATH="$PROJECT_ROOT/GhosttyKit/ghostty.h"
STAMP_FILE="$PROJECT_ROOT/.ghostty-source"
REQUIRED_ZIG_VERSION="${REQUIRED_ZIG_VERSION:-0.15.2}"
EXPECTED_STAMP="repo=${GHOSTTY_REPO}
ref=${GHOSTTY_REF}"

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

require_tool git "brew install git"

if ! xcode-select --print-path | grep -q "/Applications/Xcode.app/Contents/Developer"; then
    echo "Error: Xcode must be the active developer directory."
    echo "Run: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
    exit 1
fi

if [[ -d "$XCFRAMEWORK_DIR" && -f "$STAMP_FILE" ]] && [[ "$(cat "$STAMP_FILE")" == "$EXPECTED_STAMP" ]]; then
    echo "==> GhosttyKit.xcframework already matches $GHOSTTY_REPO@$GHOSTTY_REF"
    exit 0
fi

if [[ -d "$XCFRAMEWORK_DIR" ]]; then
    echo "==> Removing existing GhosttyKit.xcframework"
    rm -rf "$XCFRAMEWORK_DIR"
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
    curl -fsSL "$ZIG_URL" -o "$ZIG_DIR/$ZIG_ARCHIVE"
    tar -xf "$ZIG_DIR/$ZIG_ARCHIVE" -C "$ZIG_DIR"
    ZIG_BIN="$ZIG_DIR/zig-${ZIG_ARCH}-macos-${REQUIRED_ZIG_VERSION}/zig"
fi

echo "==> Cloning $GHOSTTY_REPO@$GHOSTTY_REF"
git clone --depth 1 --branch "$GHOSTTY_REF" "$GHOSTTY_URL" "$WORK_DIR/ghostty"
git -C "$WORK_DIR/ghostty" submodule update --init --recursive --depth 1

echo "==> Building GhosttyKit.xcframework from upstream source"
(
    cd "$WORK_DIR/ghostty"
    "$ZIG_BIN" build \
        -Doptimize=ReleaseFast \
        -Demit-xcframework=true \
        -Dxcframework-target=universal \
        -Demit-macos-app=false
)

SOURCE_XCFRAMEWORK="$WORK_DIR/ghostty/macos/GhosttyKit.xcframework"
SOURCE_HEADER="$WORK_DIR/ghostty/include/ghostty.h"

if [[ ! -d "$SOURCE_XCFRAMEWORK" ]]; then
    echo "Error: Expected GhosttyKit.xcframework at $SOURCE_XCFRAMEWORK"
    exit 1
fi

if [[ ! -f "$SOURCE_HEADER" ]]; then
    echo "Error: Expected ghostty.h at $SOURCE_HEADER"
    exit 1
fi

echo "==> Installing GhosttyKit.xcframework"
cp -R "$SOURCE_XCFRAMEWORK" "$XCFRAMEWORK_DIR"
cp "$SOURCE_HEADER" "$HEADER_PATH"
printf "%s\n" "$EXPECTED_STAMP" > "$STAMP_FILE"

echo "==> Done"
echo "    Run 'swift build' to build the project"
