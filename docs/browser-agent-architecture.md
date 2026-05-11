# Browser Agent Architecture

Kaji owns the browser runtime. Coding agents only receive a stable local control contract.

## Goals

- Keep Chromium embedded inside Kaji.
- Never launch external Chrome for agent browser control.
- Expose CEF through Chrome DevTools Protocol first.
- Build MCP tools on top of CDP and Kaji broker state.
- Keep agent-specific configuration inside each coding agent module.

## Layers

### Runtime coordinator

`KajiBrowserRuntimeCoordinator` starts CEF once per process, allocates the remote debugging port, and publishes runtime state to the broker. Browser views do not decide process-level CEF settings.

### Control broker

`KajiBrowserControlBroker` listens on localhost and exposes token-protected browser actions for the active Kaji browser session. `KajiBrowserControlRegistry` binds visible browser panes to worktree sessions, so agents can navigate, open tabs, move history, reload, and read page text without launching an external app.

### CDP endpoint

CEF remote debugging exposes Chromium targets on localhost. Agent-browser, Chrome DevTools MCP, and Kaji's MCP adapter attach to this endpoint instead of launching Chrome.

### MCP adapter

The MCP adapter is a stdio process installed as `~/.kaji/bin/kaji-browser-mcp`. The checked-in entrypoint stays tiny and loads modular support files from `~/.kaji/bin/kaji-browser/`.

The adapter has two tool layers:

- Kaji tools talk to the broker first and expose `kaji_browser_status`, `kaji_browser_current`, `kaji_browser_navigate`, `kaji_browser_new_tab`, history, reload, read-page, and screenshot tools.
- Playwright tools are forwarded to `@playwright/mcp` through `--cdp-endpoint`, so agents get the standard `browser_*` surface for snapshots, screenshots, tabs, hover, click, keyboard, console, network, dialogs, waits, and form operations without Kaji reimplementing those tools.

The Playwright MCP process starts lazily on the first `browser_*` tool call. `tools/list` never waits for the browser panel or CDP endpoint, so agent startup stays fast even when the embedded browser is closed. Unsafe Playwright tools are hidden unless `KAJI_BROWSER_ALLOW_UNSAFE_TOOLS=1`.

## Environment contract

Kaji-launched terminals receive these values when the broker starts:

- `KAJI_BROWSER_BROKER_URL`
- `KAJI_BROWSER_MCP_TOKEN`
- `KAJI_BROWSER_SESSION_ID`
- `KAJI_BROWSER_CDP_URL`
- `KAJI_BROWSER_CDP_PORT`
- `KAJI_BROWSER_MCP_COMMAND`
- `KAJI_CODEX_BROWSER_MCP_ARGS`
- `KAJI_PI_BROWSER_MCP_CONFIG`

`KAJI_BROWSER_CDP_URL` is only present after CEF has started.

## Agent policy

- Codex: inject runtime MCP config through the Codex module.
- Claude: generate `.mcp.json` shape through the Claude module.
- OpenCode: generate OpenCode MCP config through the OpenCode module.
- Pi: write a Kaji-owned MCP config and launch with `--mcp-config` through the Pi module.
- Shims only route executables and environment. They should not contain browser-specific protocol logic.
