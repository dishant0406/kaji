#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNTIME_DIR="$PROJECT_ROOT/KajiMonacoRuntime"
OUTPUT_DIR="$PROJECT_ROOT/Kaji/Resources/MonacoEditor"

build_with_bun() {
    (
        cd "$RUNTIME_DIR"
        bun install
        bun run check
        bun run build
    )
}

build_static_fallback() {
    echo "Error: Bun is required to build the Monaco runtime." >&2
    echo "Install Bun or use the committed Kaji/Resources/MonacoEditor build output." >&2
    exit 1
}

if command -v bun >/dev/null 2>&1; then
    build_with_bun
else
    echo "==> Bun not found; building Monaco static fallback with Python"
    build_static_fallback
fi

if [[ ! -f "$OUTPUT_DIR/index.html" ]]; then
    echo "Error: Monaco runtime build did not produce $OUTPUT_DIR/index.html"
    exit 1
fi

if [[ ! -f "$OUTPUT_DIR/assets/index.js" && ! -f "$OUTPUT_DIR/vs/loader.js" ]]; then
    echo "Error: Monaco runtime build did not produce a runnable JavaScript entrypoint"
    exit 1
fi
