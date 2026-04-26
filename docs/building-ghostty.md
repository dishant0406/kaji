# GhosttyKit

Droid embeds libghostty through `GhosttyKit.xcframework/`. The repo now builds that xcframework directly from the official upstream source at [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty).

## Requirements

- Xcode selected as the active developer directory
- `gettext` installed locally

Ghostty's current official build docs list Zig `0.15.2` for `1.3.x` and `tip`, and require Xcode plus the macOS/iOS SDKs and Metal Toolchain on macOS. `scripts/setup.sh` uses a matching local Zig when present and otherwise downloads Zig `0.15.2` temporarily for the build.

## Local Setup

```bash
scripts/setup.sh
```

The setup script:

1. Clones `ghostty-org/ghostty` at `main` by default
2. Builds `macos/GhosttyKit.xcframework` with Zig
3. Copies the xcframework into this repo
4. Syncs `include/ghostty.h` into `GhosttyKit/ghostty.h`

## Pinning Upstream

If you want to build against a specific upstream tag or branch, set `GHOSTTY_REF`:

```bash
GHOSTTY_REF=v1.3.0 scripts/setup.sh
```

You can also override the repo slug entirely:

```bash
GHOSTTY_REPO=ghostty-org/ghostty GHOSTTY_REF=main scripts/setup.sh
```

## Build Command

`scripts/setup.sh` uses the upstream xcframework build path exposed by Ghostty's macOS build:

```bash
zig build \
  -Doptimize=ReleaseFast \
  -Demit-xcframework=true \
  -Dxcframework-target=universal \
  -Demit-macos-app=false
```

`Package.swift` links against `GhosttyKit.xcframework/macos-arm64_x86_64/ghostty-internal.a`.
