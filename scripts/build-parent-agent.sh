#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PI_ROOT="$PROJECT_ROOT/Vendor/pi-mono"
OUT_DIR="$PROJECT_ROOT/Kaji/Resources/pi"

if [[ ! -d "$PI_ROOT" ]]; then
    echo "Error: vendored Pi runtime not found at $PI_ROOT" >&2
    exit 1
fi

if ! command -v node >/dev/null 2>&1; then
    echo "Error: Node.js is required to build the parent agent runtime. Install with: brew install node" >&2
    exit 1
fi

if [[ ! -d "$PI_ROOT/node_modules" ]]; then
    echo "==> Installing parent agent dependencies"
    npm install --prefix "$PI_ROOT"
fi

echo "==> Building Pi runtime packages"
npm --prefix "$PI_ROOT/packages/ai" run build
npm --prefix "$PI_ROOT/packages/agent" run build

mkdir -p "$OUT_DIR"

echo "==> Bundling Kaji parent agent runtime"
"$PI_ROOT/node_modules/.bin/esbuild" \
    "$PI_ROOT/packages/kaji-agent/src/main.ts" \
    --bundle \
    --platform=node \
    --format=esm \
    --target=node20 \
    --outfile="$OUT_DIR/kaji-agent.mjs" \
    --banner:js='import { createRequire } from "module"; const require = createRequire(import.meta.url);'

"$PI_ROOT/node_modules/.bin/esbuild" \
    "$PI_ROOT/packages/kaji-agent/src/oauth-login.ts" \
    --bundle \
    --platform=node \
    --format=esm \
    --target=node20 \
    --outfile="$OUT_DIR/oauth-login.mjs" \
    --banner:js='import { createRequire } from "module"; const require = createRequire(import.meta.url);'

echo "==> Parent agent runtime ready in $OUT_DIR"
