#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_ROOT="$PROJECT_ROOT/.build-support/zlob"
SOURCE_DIR="$BUILD_ROOT/source"
OUT_DIR="$PROJECT_ROOT/Kaji/Resources/Zlob"
PINNED_TAG="v1.4.2"
REQUIRED_ZIG_VERSION="${REQUIRED_ZIG_VERSION:-0.16.0}"

ZIG_BIN="zig"
if ! command -v zig >/dev/null 2>&1 || [[ "$(zig version)" != "$REQUIRED_ZIG_VERSION" ]]; then
    case "$(uname -m)" in
        arm64) ZIG_ARCH="aarch64" ;;
        x86_64) ZIG_ARCH="x86_64" ;;
        *)
            echo "Error: Unsupported macOS architecture $(uname -m)" >&2
            exit 1
            ;;
    esac

    ZIG_DIR="$BUILD_ROOT/zig"
    mkdir -p "$ZIG_DIR"
    ZIG_ARCHIVE="zig-${ZIG_ARCH}-macos-${REQUIRED_ZIG_VERSION}.tar.xz"
    ZIG_URL="https://ziglang.org/download/${REQUIRED_ZIG_VERSION}/${ZIG_ARCHIVE}"

    echo "==> Downloading Zig $REQUIRED_ZIG_VERSION for zlob build"
    curl --fail --location --show-error --retry 5 --retry-delay 5 --retry-all-errors "$ZIG_URL" -o "$ZIG_DIR/$ZIG_ARCHIVE"
    tar -xf "$ZIG_DIR/$ZIG_ARCHIVE" -C "$ZIG_DIR"
    ZIG_BIN="$ZIG_DIR/zig-${ZIG_ARCH}-macos-${REQUIRED_ZIG_VERSION}/zig"
fi

mkdir -p "$BUILD_ROOT"

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
    rm -rf "$SOURCE_DIR"
    git clone --depth 1 --branch "$PINNED_TAG" https://github.com/dmtrKovalenko/zlob.git "$SOURCE_DIR"
else
    git -C "$SOURCE_DIR" fetch --depth 1 origin "refs/tags/$PINNED_TAG:refs/tags/$PINNED_TAG"
    git -C "$SOURCE_DIR" checkout "$PINNED_TAG"
fi

echo "==> Building zlob $PINNED_TAG with Zig $REQUIRED_ZIG_VERSION"
"$ZIG_BIN" build \
    -Doptimize=ReleaseFast \
    --summary none \
    --global-cache-dir "$BUILD_ROOT/zig-cache" \
    --cache-dir "$BUILD_ROOT/local-cache" \
    --build-file "$SOURCE_DIR/build.zig" \
    --prefix "$BUILD_ROOT/out"

mkdir -p "$OUT_DIR"
cp "$BUILD_ROOT/out/bin/zlob" "$OUT_DIR/zlob"
chmod +x "$OUT_DIR/zlob"

echo "==> zlob ready at $OUT_DIR/zlob"
