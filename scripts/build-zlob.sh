#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_ROOT="$PROJECT_ROOT/.build-support/zlob"
SOURCE_DIR="$BUILD_ROOT/source"
OUT_DIR="$PROJECT_ROOT/Kaji/Resources/Zlob"
PINNED_TAG="v1.4.2"

if ! command -v zig >/dev/null 2>&1; then
    echo "Error: Zig 0.16.x is required to build zlob" >&2
    exit 1
fi

ZIG_VERSION="$(zig version)"
case "$ZIG_VERSION" in
    0.16.*) ;;
    *)
        echo "Error: Zig 0.16.x is required, found $ZIG_VERSION" >&2
        exit 1
        ;;
esac

mkdir -p "$BUILD_ROOT"

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
    rm -rf "$SOURCE_DIR"
    git clone --depth 1 --branch "$PINNED_TAG" https://github.com/dmtrKovalenko/zlob.git "$SOURCE_DIR"
else
    git -C "$SOURCE_DIR" fetch --depth 1 origin "refs/tags/$PINNED_TAG:refs/tags/$PINNED_TAG"
    git -C "$SOURCE_DIR" checkout "$PINNED_TAG"
fi

echo "==> Building zlob $PINNED_TAG with Zig $ZIG_VERSION"
zig build -Doptimize=ReleaseFast --summary none --global-cache-dir "$BUILD_ROOT/zig-cache" --cache-dir "$BUILD_ROOT/local-cache" --build-file "$SOURCE_DIR/build.zig" --prefix "$BUILD_ROOT/out"

mkdir -p "$OUT_DIR"
cp "$BUILD_ROOT/out/bin/zlob" "$OUT_DIR/zlob"
chmod +x "$OUT_DIR/zlob"

echo "==> zlob ready at $OUT_DIR/zlob"
