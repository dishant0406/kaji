#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ICON_SOURCE="$PROJECT_ROOT/Kaji/Resources/Assets.xcassets/AppIcon.appiconset"
OUTPUT_PATH="${1:-$PROJECT_ROOT/build/AppIcon.icns}"

ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET_DIR"
mkdir -p "$(dirname "$OUTPUT_PATH")"

cp "$ICON_SOURCE/icon_16.png"     "$ICONSET_DIR/icon_16x16.png"
cp "$ICON_SOURCE/icon_16@2x.png"  "$ICONSET_DIR/icon_16x16@2x.png"
cp "$ICON_SOURCE/icon_32.png"     "$ICONSET_DIR/icon_32x32.png"
cp "$ICON_SOURCE/icon_32@2x.png"  "$ICONSET_DIR/icon_32x32@2x.png"
cp "$ICON_SOURCE/icon_128.png"    "$ICONSET_DIR/icon_128x128.png"
cp "$ICON_SOURCE/icon_128@2x.png" "$ICONSET_DIR/icon_128x128@2x.png"
cp "$ICON_SOURCE/icon_256.png"    "$ICONSET_DIR/icon_256x256.png"
cp "$ICON_SOURCE/icon_256@2x.png" "$ICONSET_DIR/icon_256x256@2x.png"
cp "$ICON_SOURCE/icon_512.png"    "$ICONSET_DIR/icon_512x512.png"
cp "$ICON_SOURCE/icon_512@2x.png" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_PATH"

rm -rf "$(dirname "$ICONSET_DIR")"

echo "$OUTPUT_PATH"
