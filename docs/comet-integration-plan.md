# Comet → Kaji Native Integration Plan (v3 — single build, single process, embedded gpui)

Source: [zeronsh/comet](https://github.com/zeronsh/comet) (MIT, v0.2.29). Directive: **one Kaji build, one process** — comet's code copied into Kaji, fork gpui to embed, and keep only the UI parts we want (drop comet's sidebar/nav/shell chrome; Kaji already provides the shell). KajiCode is the only provider.

This supersedes v2 (separate window). It is the deepest option: be aware it hinges on forking gpui's macOS platform layer. The plan is gated on a 1–2 week spike that proves feasibility before committing the full build.

---

## 1. What the user chose (recorded)

- Comet's code is **vendored into Kaji's repo** and compiled **into the single Kaji binary** — no second app, no helper process.
- gpui is **forked** so its UI renders inside Kaji's SwiftUI windows instead of owning the app.
- From comet's UI we keep only the conversation surface — **transcript, composer, markdown, model picker, tool groups** — and drop its shell: sidebar, nav bar, spaces, tabs, app menus, settings pages (Kaji's own sidebar/tabs/splits/settings are the shell).

## 2. Why a fork is needed at all (constraint, stated once)

gpui's macOS backend (`gpui_platform` → `MacWindow`) creates its own `NSWindow`, registers itself as the `NSApplicationDelegate`, and expects to drive the run loop (`NSApp.run`). SwiftUI/AppKit already owns all three inside Kaji. The fork's job: make gpui run in **embedded mode** — render into a host-provided `NSView`/`CAMetalLayer`, receive events forwarded by AppKit, and never touch `NSApplication` ownership.

One genuine risk reducer: comet already builds against the split `gpui` + `gpui_platform` packages, and the mac backend sits behind a `Platform` trait — the fork is a new platform impl (or a parametrized `MacPlatform(embedded: true)`), not a rewrite of gpui core.

## 3. Target architecture — one binary, one process

```
Kaji.app (the only .app)
├── SwiftUI shell (unchanged): sidebar, tabs, Bonsplit splits, settings, menu bar
├── TerminalTab.Content.cometAgent        (new pane kind)
│   └── NSViewRepresentable → CometSurfaceView (host NSView + CAMetalLayer)
│       └── forwards keyDown/mouse/IME/resize/focus → gpui event dispatch
└── libkaji_comet (Rust staticlib, linked like TermyKit — C ABI, no rpath dance)
    ├── vendored comet: proto + doc + engine + rpc + harness(acp)   [in-proc, tokio]
    │   └── KajiCode AcpAgentSpec → `kajicode acp` subprocess
    ├── vendored comet UI subset (gpui views): transcript, composer,
    │   markdown, pickers, attachments, badges, loaders, motion, theme
    │   └── root view = one chat surface (no shell/sidebar/nav/menus)
    └── forked gpui + gpui_platform: EmbeddedMacPlatform
        └── renders into the host CAMetalLayer, zero NSApp ownership
```

- The engine runs **in-process** on tokio worker threads (comet's headed mode already does engine-in-proc; the fork removes the part that took over `NSApp.run`). UI ↔ engine via comet's existing **in-memory transport** (`memory_client`) — same protocol, no sockets.
- One Rust panic kills the app now (no process isolation). Accepted tradeoff for "one process"; mitigations in §8.
- Multiple agent panes = multiple embedded gpui surfaces, one per `cometAgent` tab, all sharing the same engine.

## 4. The gpui fork — scope definition (the make-or-break work)

New `EmbeddedMacPlatform` implementing gpui's `Platform` trait:

1. **Rendering**: bind the gpui Metal renderer to a host-provided `CAMetalLayer` (owned by Kaji's `CometSurfaceView`) instead of creating an `NSWindow`. Handle drawable size/backing-scale/resize driven by AppKit layout, and draw in step with the existing `NSApplication` run loop / `CVDisplayLink`.
2. **Events**: no global `NSEvent` monitors. Kaji's hosting `NSView` forwards `keyDown/keyUp/mouse*/scrollWheel/flagsChanged` into gpui's dispatcher; keyboard focus only when Kaji's pane is focused; `resignFirstResponder` → gpui blur.
3. **IME**: the host `NSView` implements `NSTextInputClient`; marked text/routes into gpui's input handler (the composer is a hand-rolled input — this is the finickiest part).
4. **No window chrome API**: skip menus, dock, minimize, fullscreen, window tabs, window delegations — everything Kaji doesn't need.
5. Keep upstream behavior for: executor/background threads, `Entity`/`Context`/`View` system, layout (taffy), text system, animations, list state (transcript virtualization).

Deliberately out of fork scope: multi-window, floating windows, window effects tied to `NSWindow` (Kaji's pane chrome surrounds the surface instead).

## 5. What we copy from comet — keep / drop ledger

**Keep (UI, rendered inside the Kaji pane):**

| Module | ~LOC | Notes |
| --- | --- | --- |
| `transcript.rs` | 7.6k | virtualized transcript, block rows, tool groups, stick-to-bottom |
| `composer.rs` | 7.2k | input, send→steer→stop morph, question panel |
| `markdown/` | ~4k | streaming markdown stack |
| `pickers.rs` (subset) | ~1k | model/reasoning picker only (repo/branch pickers dropped — Kaji owns projects) |
| `state.rs` (trim) | ~2k | engine bootstrap → in-proc; drop spaces/tabs routing |
| `attachments`, `badges`, `loaders`, `notify`, `sound`, `links`, `syntax_cache` | ~3k | as-is |
| `motion.rs`, `theme.rs`, `typography.rs` | ~2k | paint-only; Kaji theme colors fed into comet's theme registry |

**Drop (shell chrome Kaji replaces):** `shell.rs` (8.5k), `shell/spaces.rs` (3.1k), `shell/tabs.rs`, `app_menus.rs`, `settings*`, `rail.rs`, `history.rs`, `frost.rs`/`edge_fade.rs` (window-glass effects meaningless inside a pane), terminal panel (Kaji has Termy), changes.rs diff pane (Kaji's `DiffViewerPane` renders comet's diff data instead).

**Keep (core, unchanged):** `proto`, `doc` (Loro session docs, command ledger), `engine` (minus auth/sync/uploads/terminals/repos/local_import), `rpc` (in-memory only), `harness` ACP module + `mock`.

Net UI kept ≈ 26–28k LOC of comet's ~60k — "take the code of what we want", literally.

## 6. KajiCode provider wire (unchanged — still the critical dependency)

`kajicode` is a terminal CLI today (no event stream, `resume: .unsupported`, static model list). Comet's engine needs a wire:

**Add `kajicode acp` — ACP-over-stdio mode**, consumed by comet's existing `AcpHarness` through one `AcpAgentSpec` (~40 LOC + registry entry): `initialize`, `session/new`, `session/load` (resume), `session/prompt` + streamed `session/update`, `session/cancel`, permission requests, model advertisement, `availableCommands`. Turn ends must be deterministic (`stopReason`) so we stay off comet's ACP watchdog path. Ships via the existing `kaji-channel.json` + `protocolVersion` gating.

## 7. Build & packaging (single binary)

- Vendored workspace `vendor/comet/` (pinned rev) + `vendor/gpui-fork/`; built as a **staticlib** `libkaji_comet.a` with a hand-written C ABI header — exactly the TermyKit pattern (C modulemap + `-L/-l` unsafeFlags link, already proven with libtermy), minus the dylib/rpath part.
- Rust→Swift calls: `cometkit_init`, `cometkit_attach_surface(handle, nsView, config)`, `cometkit_detach_surface`, `cometkit_send_command(handle, json)`, `cometkit_set_theme(colors)`. Rust→Swift: one callback fn-pointer for engine events Kaji's Mission Control needs (or Swift reads via the same callback channel) — kept minimal; the conversation UI is entirely gpui-side.
- `scripts/setup.sh` gains the comet pin + `cargo build --release` staticlib step; `scripts/build-release.sh` unchanged (single binary to sign/notarize — simpler than v2's nested app).

## 8. Risks (ranked) & mitigations

1. **Embedded gpui feasibility** — the fork is the whole ballgame. **Gate the project on a Phase-0 spike**: render Zed's `examples/input.rs` text input inside a SwiftUI-hosted `NSView` with forwarding + IME, using the forked platform. If the spike fails, fall back to v2 (single build, bundled internal window) — the vendoring/trim work is shared.
2. **Sustained fork maintenance** — gpui is already a custom fork (comet pins `wingleeio/zed@e2ddcc…`); ours adds an embedded platform. Mitigate: keep the fork as a small patch series on the pinned rev; never take upstream casually; CI builds the spike app on every bump.
3. **In-process stability** — a Rust panic now takes Kaji down. Mitigate: `panic = "abort"` off for the staticlib, catch_unwind at the FFI boundary, watchdog thread + automatic surface re-init, and Kaji's existing crash reporting hooked into the Rust side.
4. **IME/focus/shortcut interleaving** — two event consumers in one window. Mitigate: spike covers IME; Kaji's keymap defers to the pane when focused; exhaustive manual matrix (IME CN/JP input, cmd-key chords, Stage Manager, fullscreen splits).
5. **Metal layer inside SwiftUI hierarchy** — resizing/theme/dark-mode sync. Mitigate: host view drives geometry; theme colors flow Kaji → comet theme registry (no comet settings UI).
6. **KajiCode ACP turn-end reliability** — as v1/v2: deterministic `stopReason` + scripted fixture tests.
7. **Threading** — tokio (engine) + gpui executor + SwiftUI main thread in one process. Mitigate: FFI boundary is main-actor-only; engine callbacks hop to main; comet's `gpui_tokio` bridge pattern reused.

## 9. Phases & effort (honest numbers)

| Phase | Scope | Est. |
| --- | --- | --- |
| 0 | **Spike (go/no-go):** gpui fork renders `input.rs` example inside SwiftUI-hosted NSView; keyboard + IME + resize work | 1–2 wk |
| 1 | KajiCode ACP mode (KajiCode repo, parallel) | 1–2 wk |
| 2 | Vendor comet, trim to §5 ledger, staticlib + C ABI boots engine in-proc, mock harness round-trip from Swift | 1–2 wk |
| 3 | Embedded platform hardening: full event matrix, IME, focus, multi-surface | 2–4 wk |
| 4 | Wire transcript/composer/markdown surface into `TerminalTab.Content.cometAgent`; theme/color sync; KajiCode spec entry | 2–3 wk |
| 5 | Diff data → Kaji's DiffViewerPane; Mission Control feed via engine events; attachments | 1–2 wk |
| 6 | Packaging, tests (Swift Testing + Rust), `architecture.md`, release gating | 1 wk |

Total ≈ **9–14 weeks**, front-loaded risk: Phase 0 decides everything. (v2 was 5–7 wk; this buys a true single-process, in-pane experience at roughly double cost.)

## 10. Definition of done

One `Kaji.app`. An agent pane opened in any split renders comet's transcript/composer (and nothing of comet's shell) as a native-feeling pane: streaming markdown, tool groups, question panel, steering, resume, KajiCode-only over ACP, transcripts persisted by the Loro engine in `~/Library/Application Support/Kaji/comet-engine/`, live status in Mission Control, no second process, no second window, no Dock entry, no menu-bar handoff.
