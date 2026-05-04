# Pi Package Research For Droid

## Summary

Pi now has a real package ecosystem. The official catalog at `https://pi.dev/packages` lists thousands of extensions, skills, prompt templates, and themes installable with `pi install npm:<package>` or git/package sources.

Droid should not blindly install Pi packages into the parent agent yet. Droid's Parent Agent currently uses a custom vendored Pi runtime (`Vendor/pi-mono/packages/droid-agent`) rather than the full Pi TUI extension loader. Most packages are therefore either:

- Ideas to port into native Droid tools and UI.
- Packages that require explicit extension-loader support in Droid's parent runtime.
- Packages that only make sense inside standalone Pi CLI sessions.

## Best Candidates

| Package | Why It Matters For Droid | Recommendation |
| --- | --- | --- |
| `pi-mcp-adapter` | Uses MCP servers without injecting huge tool schemas into context. Supports lazy servers, direct tools, `.mcp.json`, and imports from Claude/Cursor/Codex configs. | High priority. Add native MCP support or integrate this adapter. |
| `pi-web-access` | Web search, URL fetch, GitHub repo cloning, PDF extraction, YouTube/local video understanding. | High priority for Parent Agent research. |
| `pi-lens` | LSP, linters, formatters, type-checking, secret scan, read-before-edit guard, diagnostics after writes. | High-value but heavy. Make optional as a Droid quality/diagnostics integration. |
| `pi-ask-user` | Structured `ask_user` tool with searchable options, multi-select, freeform input, timeout, and structured result details. | Droid already has native ask-user UI. Align with this schema and render natively. |
| `pi-subagents` | Scout/planner/worker/reviewer/oracle delegation, chains, parallel runs, background jobs, worktree isolation. | Use as design reference. Avoid direct install until Droid's orchestration boundaries are clear. |
| `taskplane` | Full task orchestration with DAGs, worktrees, reviewers, merger agents, dashboard. | Architecture reference for long-running project mode; too heavy for first integration. |
| `pi-crew` | Coordinated teams, async runs, mailbox, worktrees, durable state, dashboard, autonomous routing. | Architecture reference; not an immediate dependency. |
| `@spences10/pi-context` | SQLite sidecar for storing large tool output with FTS retrieval and compact receipts. | Very relevant for Parent/Child Agent output overflow. |
| `@samfp/pi-memory` / `@luxusai/pi-hindsight` | Persistent memory, learned preferences, and session patterns. | Evaluate later with privacy/security constraints. |
| `rytswd/pi-agent-extensions` | Practical collection: permission gate, slow-mode edit review, fetch, direnv, notify, stash, statusline, questionnaire. | Port selected pieces natively. |
| `pi-depo` | Declarative package manager for Pi packages, skills, hooks, and MCP servers via `kit.yml`. | Useful if Droid gets a package marketplace/sync system. |
| `pi-docparser` | Parses PDFs, Office docs, spreadsheets, and images. | Useful for attachments and file ingestion. |
| `pi-smart-fetch` | Browser-like TLS and content extraction for web fetches. | Alternative or supplement to `pi-web-access`. |
| `pi-markdown-preview`, `pi-mermaid`, `@walterra/pi-charts` | Better rendering for markdown, Mermaid, and charts. | Droid should render natively; use these as references. |
| `pi-studio` | Two-pane browser workspace with prompt/response editing and previews. | Reference only. Droid already owns native UI. |
| `pi-interactive-shell` | Runs other coding agents inside Pi overlays with supervision. | Not needed directly; Droid already runs agents in native terminal panes. |

## Highest-Value Droid Integrations

### 1. MCP Support

Use `pi-mcp-adapter` as the reference or dependency.

Benefits:

- Unlock Chrome DevTools, Figma, GitHub, databases, docs, local services, and other MCP tools.
- Avoid tool-schema context bloat by using lazy discovery/proxy mode.
- Reuse existing `.mcp.json` and host-specific configs from Claude Code, Cursor, Codex, etc.

Implementation direction:

- Add a Droid Parent Agent tool like `droid.mcp` or expose Pi-compatible `mcp`.
- Prefer lazy server startup and cached metadata.
- Render MCP setup/config in native Settings later.

### 2. Web Research Tools

Use `pi-web-access` as the primary reference.

Useful capabilities:

- `web_search`
- `code_search`
- `fetch_content`
- GitHub repo cloning for source inspection
- PDF extraction
- YouTube/local video understanding
- Blocked-page fallbacks

Implementation direction:

- Add native Droid parent tools for search/fetch first.
- Keep browser-cookie extraction opt-in.
- Store large fetched content in a local sidecar instead of injecting everything into context.

### 3. Output Sidecar / Context Store

Use `@spences10/pi-context` as the reference.

Problem it solves:

- Child-agent transcripts, tool output, diffs, and web fetches can exceed useful context size.

Implementation direction:

- Add a local SQLite or JSONL-backed store for large outputs.
- Return compact receipts to the parent model.
- Provide tools like `context_search`, `context_get`, and `context_list` scoped by project/session/run.

### 4. Native Ask User Schema

Droid already has a native question prompt. Align it with `pi-ask-user` rather than inventing another shape.

Recommended parameters:

- `question`
- `context`
- `options`
- `allowMultiple`
- `allowFreeform`
- `allowComment`
- `timeout`

Recommended result details:

- selection vs freeform response
- selected option values
- optional comment
- cancelled/timeout state

### 5. Safety Gates

Use `rytswd/pi-agent-extensions` and Pi examples as references.

Best ideas to port:

- `permission-gate`: block or confirm dangerous bash commands.
- `protected-paths`: protect `.env`, `.git`, `node_modules`, credentials, generated artifacts.
- `slow-mode`: approve/reject edits or writes before mutation.
- `dirty-repo-guard`: prevent unsafe session/task switches with uncommitted work.
- `direnv`: ensure project env is loaded consistently.

## What Not To Add First

- Full orchestration packages (`taskplane`, `pi-crew`, `pi-subagents`) as direct dependencies. Droid already has a Parent Agent and child-agent model; adding a second orchestration layer risks duplicated state, unclear ownership, and conflicting worktree/session control.
- Heavy UI packages (`pi-studio`, `glimpseui`) as embedded UI. Droid should remain native macOS UI.
- Social/productivity integrations like WhatsApp or Notion before coding-agent fundamentals are stable.

## Proposed Droid Roadmap

### Phase 1: Catalog And Compatibility

- Add a Settings or Parent Agent panel that can browse/search `pi.dev/packages` metadata.
- Show package name, type, description, downloads, repo, install command, and trust warning.
- Classify packages:
  - Native-compatible
  - Pi-child-compatible
  - Reference-only
  - Unsafe/unknown

### Phase 2: Native Tool Ports

Implement Droid-native equivalents for:

- `ask_user`
- `web_search`
- `fetch_content`
- `mcp`
- `context_search`
- `context_get`
- dangerous command permission gate
- protected paths
- diagnostics/verification summaries

### Phase 3: Optional Extension Loader

- Evaluate loading Pi extension factories through Pi's `ResourceLoader`/extension API in Droid's parent-agent runtime.
- Add strict allowlists and package trust UX before executing third-party code.
- Prefer project-local opt-in over global auto-loading.

### Phase 4: Recommended Pack

Create a curated Droid-recommended package set:

- MCP support
- Web access
- ask-user schema/native equivalent
- context sidecar
- safety gates
- optional `pi-lens` diagnostics

## Sources

- Official package catalog: `https://pi.dev/packages`
- Pi extension docs: `Vendor/pi-mono/packages/coding-agent/docs/extensions.md`
- Pi package docs: `Vendor/pi-mono/packages/coding-agent/docs/packages.md`
- Pi examples: `Vendor/pi-mono/packages/coding-agent/examples/extensions/README.md`
- `pi-subagents`: `https://pi.dev/packages/pi-subagents`
- `pi-web-access`: `https://pi.dev/packages/pi-web-access`
- `pi-lens`: `https://pi.dev/packages/pi-lens`
- `pi-mcp-adapter`: `https://pi.dev/packages/pi-mcp-adapter`
- `pi-ask-user`: `https://pi.dev/packages/pi-ask-user`
- `taskplane`: `https://pi.dev/packages/taskplane`
- `pi-crew`: `https://pi.dev/packages/pi-crew`
- `rytswd/pi-agent-extensions`: `https://github.com/rytswd/pi-agent-extensions`
