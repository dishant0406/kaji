#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNTIME_ROOT="$PROJECT_ROOT/KajiParentAgentRuntime"
OUT_DIR="$PROJECT_ROOT/Kaji/Resources/pi"

if [[ ! -d "$RUNTIME_ROOT" ]]; then
    echo "Error: Kaji parent agent runtime not found at $RUNTIME_ROOT" >&2
    exit 1
fi

if ! command -v node >/dev/null 2>&1; then
    echo "Error: Node.js is required to build the parent agent runtime. Install with: brew install node" >&2
    exit 1
fi

if [[ ! -d "$RUNTIME_ROOT/node_modules" ]]; then
    echo "==> Installing parent agent dependencies"
    npm ci --prefix "$RUNTIME_ROOT"
fi

echo "==> Type-checking Kaji parent agent runtime"
npm --prefix "$RUNTIME_ROOT" run check

mkdir -p "$OUT_DIR"

echo "==> Bundling Kaji parent agent runtime"
"$RUNTIME_ROOT/node_modules/.bin/esbuild" \
    "$RUNTIME_ROOT/src/main.ts" \
    --bundle \
    --platform=node \
    --format=esm \
    --target=node22 \
    --outfile="$OUT_DIR/kaji-agent.mjs" \
    --banner:js='import { createRequire } from "module"; const require = createRequire(import.meta.url);'

"$RUNTIME_ROOT/node_modules/.bin/esbuild" \
    "$RUNTIME_ROOT/src/oauth-login.ts" \
    --bundle \
    --platform=node \
    --format=esm \
    --target=node22 \
    --outfile="$OUT_DIR/oauth-login.mjs" \
    --banner:js='import { createRequire } from "module"; const require = createRequire(import.meta.url);'

perl -pi -e 's/[ \t]+$//' "$OUT_DIR/kaji-agent.mjs" "$OUT_DIR/oauth-login.mjs"
perl -pi -e 's#https://github\.com/colinhacks/zod/commit/[0-9a-f]{40}#https://github.com/colinhacks/zod/commit/<redacted>#g' "$OUT_DIR/kaji-agent.mjs" "$OUT_DIR/oauth-login.mjs"

echo "==> Parent agent runtime ready in $OUT_DIR"
