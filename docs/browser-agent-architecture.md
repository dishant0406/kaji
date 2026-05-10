# Browser Agent Architecture

Droid owns the browser runtime. Coding agents only receive a stable local control contract.

## Goals

- Keep Chromium embedded inside Droid.
- Never launch external Chrome for agent browser control.
- Expose CEF through Chrome DevTools Protocol first.
- Build MCP tools on top of CDP and Droid broker state.
- Keep agent-specific configuration inside each coding agent module.

## Layers

### Runtime coordinator

`DroidBrowserRuntimeCoordinator` starts CEF once per process, allocates the remote debugging port, and publishes runtime state to the broker. Browser views do not decide process-level CEF settings.

### Control broker

`DroidBrowserControlBroker` listens on localhost and exposes token-protected browser actions for the active Droid browser session. `DroidBrowserControlRegistry` binds visible browser panes to worktree sessions, so agents can navigate, open tabs, move history, reload, and read page text without launching an external app.

### CDP endpoint

CEF remote debugging exposes Chromium targets on localhost. Agent-browser, Chrome DevTools MCP, and Droid's MCP adapter attach to this endpoint instead of launching Chrome.

### MCP adapter

The MCP adapter is a stdio process installed as `~/.droid/bin/droid-browser-mcp`. The checked-in entrypoint stays tiny and loads modular support files from `~/.droid/bin/droid-browser/`.

The adapter has two tool layers:

- Droid tools talk to the broker first and expose `droid_browser_status`, `droid_browser_current`, `droid_browser_navigate`, `droid_browser_new_tab`, history, reload, read-page, and screenshot tools.
- Playwright tools are forwarded to `@playwright/mcp` through `--cdp-endpoint`, so agents get the standard `browser_*` surface for snapshots, screenshots, tabs, hover, click, keyboard, console, network, dialogs, waits, and form operations without Droid reimplementing those tools.

The Playwright MCP process starts lazily on the first `browser_*` tool call. `tools/list` never waits for the browser panel or CDP endpoint, so agent startup stays fast even when the embedded browser is closed. Unsafe Playwright tools are hidden unless `DROID_BROWSER_ALLOW_UNSAFE_TOOLS=1`.

## Environment contract

Droid-launched terminals receive these values when the broker starts:

- `DROID_BROWSER_BROKER_URL`
- `DROID_BROWSER_MCP_TOKEN`
- `DROID_BROWSER_SESSION_ID`
- `DROID_BROWSER_CDP_URL`
- `DROID_BROWSER_CDP_PORT`
- `DROID_BROWSER_MCP_COMMAND`
- `DROID_CODEX_BROWSER_MCP_ARGS`
- `DROID_PI_BROWSER_MCP_CONFIG`

`DROID_BROWSER_CDP_URL` is only present after CEF has started.

## Agent policy

- Codex: inject runtime MCP config through the Codex module.
- Claude: generate `.mcp.json` shape through the Claude module.
- OpenCode: generate OpenCode MCP config through the OpenCode module.
- Pi: write a Droid-owned MCP config and launch with `--mcp-config` through the Pi module.
- Shims only route executables and environment. They should not contain browser-specific protocol logic.
