#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RIFT_REPO="${RIFT_REPO:-anomalyco/rift}"
RIFT_REF="${RIFT_REF:-18ca9d199cfa0033e1adf63b1eb6625fab89478a}"
RIFT_URL="https://github.com/${RIFT_REPO}.git"
RIFT_PROFILE="${RIFT_PROFILE:-release}"
RIFT_BUILD_FLAG="--release"
RIFT_TARGET_DIR="${RIFT_TARGET_DIR:-}"
RESOURCE_DIR="$PROJECT_ROOT/Kaji/Resources/Rift"
BINARY_PATH="$RESOURCE_DIR/rift"
STAMP_FILE="$PROJECT_ROOT/.rift-source"
PATCH_FILE="$PROJECT_ROOT/patches/rift-apfs-provenance-xattr.patch"
EXPECTED_STAMP="repo=${RIFT_REPO}
ref=${RIFT_REF}
profile=${RIFT_PROFILE}
artifact=rift
kaji_patches=apfs_provenance_xattr"

if [[ "$RIFT_PROFILE" != "release" ]]; then
    RIFT_BUILD_FLAG="--profile=$RIFT_PROFILE"
fi

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

clone_rift() {
    local destination="$1"
    if git ls-remote --exit-code --heads "$RIFT_URL" "$RIFT_REF" >/dev/null 2>&1; then
        git clone --depth 1 --branch "$RIFT_REF" "$RIFT_URL" "$destination"
    else
        git clone --depth 1 --no-checkout "$RIFT_URL" "$destination"
        git -C "$destination" fetch --depth 1 origin "$RIFT_REF"
        git -C "$destination" checkout --detach FETCH_HEAD
    fi
}

require_tool git "brew install git"
require_tool cargo "curl https://sh.rustup.rs -sSf | sh"

if [[ "${RIFT_FORCE_REBUILD:-0}" != "1" ]] \
    && [[ -f "$BINARY_PATH" && -f "$STAMP_FILE" ]] \
    && [[ "$(cat "$STAMP_FILE")" == "$EXPECTED_STAMP" ]]; then
    echo "==> Rift already matches $RIFT_REPO@$RIFT_REF"
    exit 0
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

SOURCE_DIR="$WORK_DIR/rift"
echo "==> Cloning $RIFT_REPO@$RIFT_REF"
clone_rift "$SOURCE_DIR"

if [[ -f "$PATCH_FILE" ]]; then
    echo "==> Applying Kaji Rift patches"
    git -C "$SOURCE_DIR" apply "$PATCH_FILE"
fi

BUILD_TARGET_DIR="$SOURCE_DIR/target"
if [[ -n "$RIFT_TARGET_DIR" ]]; then
    BUILD_TARGET_DIR="$RIFT_TARGET_DIR"
fi

echo "==> Building Rift"
(
    cd "$SOURCE_DIR"
    CARGO_TARGET_DIR="$BUILD_TARGET_DIR" cargo build -p rift-cli "$RIFT_BUILD_FLAG" --locked
)

SOURCE_BINARY="$BUILD_TARGET_DIR/$RIFT_PROFILE/rift"
if [[ ! -f "$SOURCE_BINARY" ]]; then
    echo "Error: Expected Rift binary at $SOURCE_BINARY"
    exit 1
fi

echo "==> Installing Rift resource"
mkdir -p "$RESOURCE_DIR"
cp "$SOURCE_BINARY" "$BINARY_PATH"
chmod 755 "$BINARY_PATH"
printf "%s\n" "$EXPECTED_STAMP" > "$STAMP_FILE"

echo "==> Done"
