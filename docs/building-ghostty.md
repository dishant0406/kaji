# GhosttyKit

Kaji embeds official upstream libghostty through `GhosttyKit.xcframework/`. The repo builds that xcframework from [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty), pinned to commit `d5d8cef4d3834cc8999eb9344066b0960b033f2d`.

## Requirements

- Xcode selected as the active developer directory
- `gettext` installed locally

Ghostty's current official build docs list Zig `0.15.2` for `1.3.x` and `tip`, and require Xcode plus the macOS/iOS SDKs and Metal Toolchain on macOS. `scripts/setup.sh` uses a matching local Zig when present and otherwise downloads Zig `0.15.2` temporarily for the build.

## Local Setup

```bash
scripts/setup.sh
```

The setup script:

1. Clones `ghostty-org/ghostty` at commit `d5d8cef4d3834cc8999eb9344066b0960b033f2d` by default
2. Builds `macos/GhosttyKit.xcframework` with Zig
3. Copies the xcframework into this repo
4. Syncs `include/ghostty.h` into `GhosttyKit/ghostty.h`
5. Syncs Ghostty shell integration and terminfo into `Kaji/Resources/ghostty`
6. Removes SwiftPM run/test products that statically link GhosttyKit so the next `swift build` or `swift run Kaji` relinks against the current xcframework

## Pinning Ghostty

If you want to build against a specific tag or branch, set `GHOSTTY_REF`:

```bash
GHOSTTY_REF=d5d8cef4d3834cc8999eb9344066b0960b033f2d scripts/setup.sh
```

You can also override the repo slug entirely:

```bash
GHOSTTY_REPO=dishant0406/ghostty GHOSTTY_REF=336805e5c5e7ddd759186ed234586d9b55334c0e scripts/setup.sh
```

If the stamp matches but you want to rebuild the xcframework anyway, set `GHOSTTY_FORCE_REBUILD=1`:

```bash
GHOSTTY_FORCE_REBUILD=1 scripts/setup.sh
```

## Build Command

`scripts/setup.sh` uses the xcframework build path exposed by Ghostty's macOS build:

```bash
zig build \
  -Doptimize=ReleaseFast \
  -Dcpu=baseline \
  -Demit-xcframework=true \
  -Dxcframework-target=universal \
  -Demit-macos-app=false
```

`Package.swift` links against `GhosttyKit.xcframework/macos-arm64_x86_64/ghostty-internal.a`.
