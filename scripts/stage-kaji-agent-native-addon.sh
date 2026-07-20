#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NATIVE_SOURCE_DIR="$PROJECT_ROOT/KajiAgentRuntime/node_modules/@oh-my-pi/pi-natives/native"

ARCH=""
DESTINATION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --destination)
            DESTINATION="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

fail() {
    echo "Error: $1" >&2
    exit 1
}

native_addon_name() {
    case "$1" in
        arm64)
            echo "pi_natives.darwin-arm64.node"
            ;;
        x86_64)
            echo "pi_natives.darwin-x64-baseline.node"
            ;;
        *)
            fail "unsupported architecture: $1"
            ;;
    esac
}

[[ -n "$ARCH" ]] || fail "arch is required"
[[ -n "$DESTINATION" ]] || fail "destination is required"
[[ -d "$NATIVE_SOURCE_DIR" ]] || fail "pi-natives dependency is missing; run bun install --cwd KajiAgentRuntime"

ADDON_NAME="$(native_addon_name "$ARCH")"
SOURCE="$NATIVE_SOURCE_DIR/$ADDON_NAME"
[[ -f "$SOURCE" ]] || fail "native addon missing at $SOURCE"

mkdir -p "$DESTINATION"
rm -f "$DESTINATION"/pi_natives.darwin-*.node
cp "$SOURCE" "$DESTINATION/$ADDON_NAME"
chmod 755 "$DESTINATION/$ADDON_NAME"

echo "Staged Kaji runtime native addon: $DESTINATION/$ADDON_NAME"
