#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TERMY_REPO="${TERMY_REPO:-lassejlv/termy}"
TERMY_REF="${TERMY_REF:-99cbcedcf6dc2101460e6fa61aa1dc2c2da95fd9}"
TERMY_URL="https://github.com/${TERMY_REPO}.git"
TERMY_PROFILE="${TERMY_PROFILE:-release}"
TERMY_BUILD_FLAG="--release"
TERMY_TARGET_DIR="${TERMY_TARGET_DIR:-}"
KIT_DIR="$PROJECT_ROOT/TermyKit"
LIB_DIR="$KIT_DIR/lib"
HEADER_PATH="$KIT_DIR/termy.h"
DYLIB_PATH="$LIB_DIR/libtermy_ffi.dylib"
MODULEMAP_PATH="$KIT_DIR/module.modulemap"
RUNTIME_RESOURCES_DIR="$PROJECT_ROOT/Kaji/Resources/termy"
STAMP_FILE="$PROJECT_ROOT/.termy-source"
PATCH_FILE="$PROJECT_ROOT/patches/termy-ffi-child-pid.patch"
EXPECTED_STAMP="repo=${TERMY_REPO}
ref=${TERMY_REF}
profile=${TERMY_PROFILE}
artifact=libtermy_ffi.dylib
kaji_ffi_extensions=termy_terminal_child_pid,termy_terminal_reload_config_colors,termy_terminal_selected_text"

if [[ "$TERMY_PROFILE" != "release" ]]; then
    TERMY_BUILD_FLAG="--profile=$TERMY_PROFILE"
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

invalidate_swiftpm_termy_products() {
    if [[ ! -d "$PROJECT_ROOT/.build" ]]; then
        return
    fi
    find "$PROJECT_ROOT/.build" \
        \( -path "*/debug/Kaji" -o -path "*/release/Kaji" -o -path "*/debug/KajiPackageTests.xctest" -o -path "*/release/KajiPackageTests.xctest" \) \
        -exec rm -rf {} +
    rm -rf "$PROJECT_ROOT/.build/KajiSwiftRun.app"
}

clone_termy() {
    local destination="$1"
    if git ls-remote --exit-code --heads "$TERMY_URL" "$TERMY_REF" >/dev/null 2>&1; then
        git clone --depth 1 --branch "$TERMY_REF" "$TERMY_URL" "$destination"
    else
        git clone --depth 1 --no-checkout "$TERMY_URL" "$destination"
        git -C "$destination" fetch --depth 1 origin "$TERMY_REF"
        git -C "$destination" checkout --detach FETCH_HEAD
    fi
}

install_modulemap() {
    cat > "$MODULEMAP_PATH" <<'MODULEMAP'
module TermyKit {
    header "termy.h"
    export *
}
MODULEMAP
}

require_tool git "brew install git"
require_tool cargo "curl https://sh.rustup.rs -sSf | sh"
require_tool install_name_tool "Install Xcode command line tools"

if [[ "${TERMY_FORCE_REBUILD:-0}" != "1" ]] \
    && [[ -f "$DYLIB_PATH" && -f "$HEADER_PATH" && -f "$STAMP_FILE" ]] \
    && [[ "$(cat "$STAMP_FILE")" == "$EXPECTED_STAMP" ]] \
    && nm -gU "$DYLIB_PATH" | grep -q "_termy_terminal_child_pid" \
    && nm -gU "$DYLIB_PATH" | grep -q "_termy_terminal_reload_config_colors" \
    && nm -gU "$DYLIB_PATH" | grep -q "_termy_terminal_selected_text" \
    && [[ -d "$RUNTIME_RESOURCES_DIR/shell" ]]; then
    echo "==> TermyKit already matches $TERMY_REPO@$TERMY_REF"
    echo "==> Building Rift"
    bash "$SCRIPT_DIR/build-rift.sh"
    invalidate_swiftpm_termy_products
    exit 0
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

SOURCE_DIR="$WORK_DIR/termy"
echo "==> Cloning $TERMY_REPO@$TERMY_REF"
clone_termy "$SOURCE_DIR"

if [[ -f "$PATCH_FILE" ]]; then
    echo "==> Applying Kaji libtermy FFI extensions"
    git -C "$SOURCE_DIR" apply "$PATCH_FILE"
fi

BUILD_TARGET_DIR="$SOURCE_DIR/target"
if [[ -n "$TERMY_TARGET_DIR" ]]; then
    BUILD_TARGET_DIR="$TERMY_TARGET_DIR"
fi

echo "==> Building libtermy"
(
    cd "$SOURCE_DIR"
    CARGO_TARGET_DIR="$BUILD_TARGET_DIR" cargo build -p termy_ffi "$TERMY_BUILD_FLAG"
)

SOURCE_DYLIB="$BUILD_TARGET_DIR/$TERMY_PROFILE/libtermy_ffi.dylib"
SOURCE_HEADER="$SOURCE_DIR/crates/ffi/include/termy.h"
SOURCE_SHELL_DIR="$SOURCE_DIR/assets/shell"

if [[ ! -f "$SOURCE_DYLIB" ]]; then
    echo "Error: Expected libtermy_ffi.dylib at $SOURCE_DYLIB"
    exit 1
fi
if [[ ! -f "$SOURCE_HEADER" ]]; then
    echo "Error: Expected termy.h at $SOURCE_HEADER"
    exit 1
fi
if [[ ! -d "$SOURCE_SHELL_DIR" ]]; then
    echo "Error: Expected Termy shell assets at $SOURCE_SHELL_DIR"
    exit 1
fi

echo "==> Installing TermyKit"
mkdir -p "$KIT_DIR" "$LIB_DIR" "$RUNTIME_RESOURCES_DIR"
cp "$SOURCE_HEADER" "$HEADER_PATH"
cp "$SOURCE_DYLIB" "$DYLIB_PATH"
install_name_tool -id "@rpath/libtermy_ffi.dylib" "$DYLIB_PATH"
install_modulemap
rm -rf "$RUNTIME_RESOURCES_DIR/shell"
cp -R "$SOURCE_SHELL_DIR" "$RUNTIME_RESOURCES_DIR/shell"
printf "%s\n" "$EXPECTED_STAMP" > "$STAMP_FILE"
invalidate_swiftpm_termy_products

echo "==> Building Rift"
bash "$SCRIPT_DIR/build-rift.sh"

echo "==> Building Kaji runtime"
if command -v bun >/dev/null 2>&1; then
    bash "$SCRIPT_DIR/build-kaji-agent-runtime.sh"
    bash "$SCRIPT_DIR/build-monaco-runtime.sh"
else
    echo "    Bun not found; skipping JavaScript runtime builds (install: curl -fsSL https://bun.sh/install | bash)"
fi

echo "==> Done"
echo "    Run 'swift build' to build the project"
