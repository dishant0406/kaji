#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNTIME_ROOT="$PROJECT_ROOT/KajiAgentRuntime"
OUT_DIR="$PROJECT_ROOT/Kaji/Resources/KajiAgentRuntime"

if [[ ! -d "$RUNTIME_ROOT" ]]; then
    echo "Error: Kaji Agent runtime not found at $RUNTIME_ROOT" >&2
    exit 1
fi

if ! command -v bun >/dev/null 2>&1; then
    echo "Error: Bun is required to build the Kaji Agent runtime. Install with: curl -fsSL https://bun.sh/install | bash" >&2
    exit 1
fi

if [[ ! -d "$RUNTIME_ROOT/node_modules" ]]; then
    echo "==> Installing Kaji Agent runtime dependencies"
    bun install --cwd "$RUNTIME_ROOT"
fi

echo "==> Type-checking Kaji Agent runtime"
bun run --cwd "$RUNTIME_ROOT" check:types

mkdir -p "$OUT_DIR"

echo "==> Bundling Kaji Agent runtime"
bun build \
    "$RUNTIME_ROOT/src/kaji-rpc.ts" \
    --target=bun \
    --format=esm \
    --outfile="$OUT_DIR/kaji-agent-runtime.mjs" \
    --external mupdf

perl -pi -e 's/[ \t]+$//' "$OUT_DIR/kaji-agent-runtime.mjs"

echo "==> Kaji Agent runtime ready in $OUT_DIR"
