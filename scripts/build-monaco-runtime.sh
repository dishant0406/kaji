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
    python3 - <<'PY'
import base64
import hashlib
import io
import pathlib
import shutil
import tarfile
import urllib.request

url = "https://registry.npmjs.org/monaco-editor/-/monaco-editor-0.55.1.tgz"
expected = "jz4x+TJNFHwHtwuV9vA9rMujcZRb0CEilTEwG2rRSpe/A7Jdkuj8xPKttCgOh+v/lkHy7HsZ64oj+q3xoAFl9A=="
root = pathlib.Path("Kaji/Resources/MonacoEditor")
index_html = root / "index.html"
main_js = root / "main.js"
vs_root = root / "vs"
if not index_html.exists() or not main_js.exists():
    raise SystemExit("Monaco fallback shell is missing")
with urllib.request.urlopen(url, timeout=60) as response:
    data = response.read()
digest = base64.b64encode(hashlib.sha512(data).digest()).decode()
if digest != expected:
    raise SystemExit("Monaco package integrity mismatch")
if vs_root.exists():
    shutil.rmtree(vs_root)
root.mkdir(parents=True, exist_ok=True)
with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
    for member in archive.getmembers():
        name = member.name
        prefix = "package/min/vs/"
        if not name.startswith(prefix) or member.isdir():
            continue
        target = root / name[len("package/min/"):]
        target.parent.mkdir(parents=True, exist_ok=True)
        source = archive.extractfile(member)
        if source is not None:
            target.write_bytes(source.read())
PY
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

if [[ ! -f "$OUTPUT_DIR/vs/loader.js" ]]; then
    echo "Error: Monaco runtime build did not produce $OUTPUT_DIR/vs/loader.js"
    exit 1
fi
