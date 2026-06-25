# Browser agent architecture

Kaji embeds a native macOS WebKit browser through `WKWebView`. Browser panels are controlled through Kaji's localhost broker and the bundled `kaji-browser` MCP server.

## Runtime

`BrowserWebController` owns one `KajiBrowserWebView` per retained browser page. `NativeBrowserSurface` hosts the native view in the browser pane, keeps the view mounted across tab switches, and applies responsive width profiles through AppKit layout. Cookies, localStorage, sessionStorage, login state, and site data are stored by WebKit's persistent default `WKWebsiteDataStore`.

## Navigation and popups

`KajiBrowserNavigationDelegate` updates page URL/title/loading state, routes non-web schemes to macOS, supports downloads, preserves TLS/client-certificate handling through WebKit default challenge handling, and replaces the web view after WebContent process termination. `KajiBrowserUIDelegate` handles JavaScript dialogs, file upload panels, and creates live WebKit popup windows for `window.open` so OAuth opener flows can complete.

## Automation

Kaji no longer exposes Chrome DevTools Protocol. The MCP server talks only to the Kaji broker and offers WebKit-native `kaji_browser_*` tools plus Playwright-compatible `browser_*` aliases. The compatible API covers current tab, tab list/new/select/close, navigation, resize, screenshots, JavaScript eval, ref snapshots, click, hover, drag, fill, type, fill form, select option, key press, waits, console messages, JavaScript dialogs, observed network requests, file upload, drop data/files, element text/HTML, and storage reads.

Unsupported Chromium-only features include Chrome extensions, CDP-complete network interception, HAR/trace/screencast/video recording, browser-process internals, and cross-origin iframe internals. Network tools report WebKit-observed coverage rather than CDP parity.

## MCP installation and availability

Kaji does not inject the browser MCP server into coding-agent launches. Users install or repair the bundled `kaji-browser` server explicitly from Settings, where Kaji writes normal user MCP config entries for supported agents. The installed command points at `~/.kaji/bin/kaji-browser-mcp` and carries no session-specific environment.

The session file lives at `~/.kaji/browser/session.json` and contains the broker URL, token, session ID, and update timestamp. The MCP server always exposes the full WebKit-native `kaji_browser_*` catalog plus Playwright-compatible `browser_*` aliases so agents never need to use `node_repl` or manually call the broker. When Kaji Browser is unavailable, direct browser tools return structured MCP errors with codes, recovery guidance, broker source, and session path.
