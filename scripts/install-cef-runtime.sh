#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM="macosarm64"
if [[ "$(uname -m)" == "x86_64" ]]; then
  PLATFORM="macosx64"
fi
RUNTIME_ROOT="$PROJECT_ROOT/.dev-support/cef-runtime"
DOWNLOAD_ROOT="$PROJECT_ROOT/.dev-support/cef-download"
CEF_ROOT="$RUNTIME_ROOT/cef_binary"
BUILD_ROOT="$RUNTIME_ROOT/build"
VERSION_FILE="$DOWNLOAD_ROOT/version.txt"
CEF_FRAMEWORK="$CEF_ROOT/Release/Chromium Embedded Framework.framework"
mkdir -p "$DOWNLOAD_ROOT" "$RUNTIME_ROOT"

ARCHIVE_NAME="$(python3 - <<PY
import json, urllib.request
platform = "$PLATFORM"
index = json.load(urllib.request.urlopen("https://cef-builds.spotifycdn.com/index.json"))
for build in index[platform]["versions"]:
    if any("_beta" in file["name"] for file in build["files"]):
        continue
    print(next(file["name"] for file in build["files"] if file["type"] == "standard"))
    break
PY
)"
ARCHIVE_PATH="$DOWNLOAD_ROOT/$ARCHIVE_NAME"
if [[ ! -f "$ARCHIVE_PATH" ]]; then
  curl --fail --location --output "$ARCHIVE_PATH" "https://cef-builds.spotifycdn.com/${ARCHIVE_NAME//+/%2B}"
fi
printf '%s' "$ARCHIVE_NAME" >"$VERSION_FILE"

CEF_LIB="$CEF_FRAMEWORK/Chromium Embedded Framework"
if [[ ! -d "$CEF_ROOT" || ! -s "$CEF_LIB" || "$(cat "$RUNTIME_ROOT/.archive" 2>/dev/null || true)" != "$ARCHIVE_NAME" ]]; then
  rm -rf "$CEF_ROOT" "$BUILD_ROOT" "$RUNTIME_ROOT/extracting"
  mkdir -p "$RUNTIME_ROOT/extracting"
  tar -xjf "$ARCHIVE_PATH" -C "$RUNTIME_ROOT/extracting"
  mv "$RUNTIME_ROOT"/extracting/cef_binary_* "$CEF_ROOT"
  rm -rf "$RUNTIME_ROOT/extracting"
  printf '%s' "$ARCHIVE_NAME" >"$RUNTIME_ROOT/.archive"
fi

if [[ -f "$CEF_LIB" ]]; then
  chmod u+w "$CEF_LIB"
  install_name_tool -id "@rpath/Chromium Embedded Framework.framework/Chromium Embedded Framework" "$CEF_LIB" 2>/dev/null || true
fi

if [[ ! -f "$BUILD_ROOT/libcef_dll_wrapper/libcef_dll_wrapper.a" || ! -x "$BUILD_ROOT/tests/cefsimple/Release/cefsimple Helper.app/Contents/MacOS/cefsimple Helper" ]]; then
  cmake -S "$CEF_ROOT" -B "$BUILD_ROOT" -G "Unix Makefiles" -DPROJECT_ARCH="$(uname -m)" -DCMAKE_BUILD_TYPE=Release
  JOBS="$(/usr/sbin/sysctl -n hw.ncpu 2>/dev/null || echo 4)"
  cmake --build "$BUILD_ROOT" --target libcef_dll_wrapper cefsimple -j"$JOBS"
fi
SWIFTPM_ROOT="$PROJECT_ROOT/.build/$(uname -m)-apple-macosx"
if [[ -d "$CEF_FRAMEWORK" ]]; then
  mkdir -p "$SWIFTPM_ROOT/Frameworks"
  ln -sfn "$CEF_FRAMEWORK" "$SWIFTPM_ROOT/Frameworks/Chromium Embedded Framework.framework"
  ln -sfn "$CEF_FRAMEWORK" "$BUILD_ROOT/tests/cefsimple/Release/Chromium Embedded Framework.framework"
fi
