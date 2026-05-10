#!/bin/bash
set -euo pipefail

APP_BUNDLE="${1:-}"
ARCH="${2:-}"

fail() {
    echo "Error: $1" >&2
    exit 1
}

[[ -n "$APP_BUNDLE" ]] || fail "app bundle path is required"
[[ -d "$APP_BUNDLE" ]] || fail "app bundle not found at $APP_BUNDLE"

FRAMEWORKS="$APP_BUNDLE/Contents/Frameworks"
CEF_FRAMEWORK="$FRAMEWORKS/Chromium Embedded Framework.framework"
CEF_BINARY="$CEF_FRAMEWORK/Chromium Embedded Framework"
CEF_RESOURCES="$CEF_FRAMEWORK/Resources"

[[ -d "$CEF_FRAMEWORK" ]] || fail "CEF framework missing at $CEF_FRAMEWORK"
[[ -s "$CEF_BINARY" ]] || fail "CEF framework binary missing at $CEF_BINARY"
[[ -f "$CEF_RESOURCES/icudtl.dat" ]] || fail "CEF icudtl.dat missing"
[[ -f "$CEF_RESOURCES/resources.pak" ]] || fail "CEF resources.pak missing"
[[ -f "$CEF_RESOURCES/chrome_100_percent.pak" ]] || fail "CEF chrome_100_percent.pak missing"
[[ -d "$CEF_RESOURCES/en.lproj" ]] || fail "CEF localized resources missing"

HELPER_COUNT=0
for helper in "$FRAMEWORKS"/cefsimple\ Helper*.app; do
    [[ -d "$helper" ]] || continue
    name="$(basename "$helper" .app)"
    executable="$helper/Contents/MacOS/$name"
    [[ -x "$executable" ]] || fail "CEF helper executable missing at $executable"
    HELPER_COUNT=$((HELPER_COUNT + 1))
done

[[ "$HELPER_COUNT" -ge 3 ]] || fail "expected CEF helper apps in $FRAMEWORKS"
[[ -x "$FRAMEWORKS/cefsimple Helper.app/Contents/MacOS/cefsimple Helper" ]] || fail "main CEF helper missing"
[[ -x "$FRAMEWORKS/cefsimple Helper (Renderer).app/Contents/MacOS/cefsimple Helper (Renderer)" ]] || fail "renderer CEF helper missing"

if [[ -n "$ARCH" ]]; then
    file "$CEF_BINARY" | grep -q "$ARCH" || fail "CEF framework is not built for $ARCH"
    file "$FRAMEWORKS/cefsimple Helper.app/Contents/MacOS/cefsimple Helper" | grep -q "$ARCH" || fail "CEF helper is not built for $ARCH"
fi

echo "CEF bundle validation passed"
