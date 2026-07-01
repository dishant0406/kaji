# TermyKit

Kaji embeds libtermy through the local `TermyKit/` C module. The module exposes `termy.h` and links `TermyKit/lib/libtermy_ffi.dylib`, which is built from pinned Termy source by `scripts/setup.sh`.

## Requirements

- Xcode command line tools
- Rust and Cargo
- Git

## Local Setup

```bash
scripts/setup.sh
```

The setup script:

1. Clones `lassejlv/termy` at commit `99cbcedcf6dc2101460e6fa61aa1dc2c2da95fd9` by default
2. Applies Kaji's libtermy FFI extension patch from `patches/termy-ffi-child-pid.patch`
3. Builds `cargo build -p termy_ffi --release`
4. Copies `crates/ffi/include/termy.h` into `TermyKit/termy.h`
5. Copies `target/release/libtermy_ffi.dylib` into `TermyKit/lib/`
6. Sets the dylib install name to `@rpath/libtermy_ffi.dylib`
7. Syncs Termy shell assets into `Kaji/Resources/termy/shell`
8. Removes SwiftPM products that link libtermy so the next build relinks cleanly

Kaji's FFI extensions are `termy_terminal_child_pid` and `termy_terminal_reload_config_colors`.

## Pinning Termy

Override the source commit or repo slug when needed:

```bash
TERMY_REF=99cbcedcf6dc2101460e6fa61aa1dc2c2da95fd9 scripts/setup.sh
TERMY_REPO=lassejlv/termy TERMY_REF=99cbcedcf6dc2101460e6fa61aa1dc2c2da95fd9 scripts/setup.sh
```

Force a rebuild even when `.termy-source` matches:

```bash
TERMY_FORCE_REBUILD=1 scripts/setup.sh
```

## Build Artifact Contract

`Package.swift` links `TermyKit/lib/libtermy_ffi.dylib` with an rpath into `TermyKit/lib`. Release packaging must copy this dylib beside the app binary or into a bundled framework location covered by the same rpath strategy.
