# Agent Store Roadmap

## Product Thesis

Kaji's Agents surface should stop being a notification view and become the local source of truth for AI coding work.

The user job is:

> I want to delegate coding work to terminal-native AI agents, stop babysitting terminals, and return only when there is a clear action, result, or safe artifact to review.

The Agent Store is the product and architecture foundation for that job. It owns agent runs as durable work objects, while notifications remain event delivery.

## Principles

| Principle | Meaning |
| --- | --- |
| Exact beats convenient | Prefer pane/session/worktree identity over active-project fallback. |
| Events are not runs | Notifications are point-in-time events; agent runs are task state. |
| Confidence is explicit | Weak attribution should not pretend to be exact. |
| Local-first | Transcripts, diffs, and verification state stay on the user's machine. |
| Provider-native where useful | Use Codex, Claude Code, and OpenCode session stores instead of terminal scraping. |
| Small UI, high leverage | Keep the sidebar popover compact, but make every row operational. |

## Outcome Metrics

| Metric | Definition | Target |
| --- | --- | --- |
| Wrong-session click rate | Agent row clicks that do not land on the intended pane/project/worktree. | Near zero. |
| Attention latency | Median time from permission/question/failure event to user action. | Down over time. |
| Verified completion rate | Completed runs with a passing verification result within 10 minutes. | Up over time. |
| Resume success rate | Resume actions that reopen the intended provider session. | Over 90%. |
| Completion clarity | Completed rows with task title, changed files, and final summary. | Over 80%. |
| Notification noise | Duplicate or misattributed provider rows per agent run. | Down over time. |

## Data Model Direction

### Core Run

```swift
struct AgentRun {
    let id: UUID
    let providerID: String
    var paneID: UUID?
    var projectID: UUID?
    var worktreeID: UUID?
    var sessionID: String?
    var transcriptPath: String?
    var title: String
    var status: AgentRunStatus
    var sourceConfidence: AgentSourceConfidence
    var startedAt: Date
    var lastEventAt: Date
    var events: [AgentRunEvent]
    var changedFiles: [AgentChangedFile]
    var verification: AgentVerificationState
}
```

### Status

| Status | Meaning |
| --- | --- |
| `running` | Provider is actively working. |
| `waiting` | Provider is idle but run is not complete. |
| `needsAttention` | User question, permission, or blocker. |
| `completed` | Provider completed the turn or task. |
| `failed` | Provider or command failed. |
| `verifying` | Kaji is running checks. |
| `verified` | Checks passed. |
| `verificationFailed` | Checks failed. |
| `stale` | Run disappeared or pane closed without a clean terminal event. |

### Source Confidence

| Confidence | Source |
| --- | --- |
| `exactPane` | Provider hook included `KAJI_PANE_ID` and pane still exists. |
| `exactSession` | Provider session ID/transcript path maps to a known pane/run. |
| `worktreeMatch` | Provider cwd maps to a known worktree, but pane is unknown. |
| `fallback` | Active context or detached notification fallback. |
| `unknown` | Not enough context to safely navigate. |

### Event Types

| Event | Examples |
| --- | --- |
| `started` | User prompt submitted, provider session active. |
| `transcript` | User text, assistant text, reasoning summary. |
| `tool` | Read, edit, shell command, MCP tool. |
| `attention` | Question, permission request, waiting state. |
| `fileChange` | File touched, diff stat changed. |
| `completed` | Final assistant message or task complete. |
| `failed` | Command failure, provider error. |
| `verification` | Build/test/lint started or finished. |

## Version Plan

## Agent Store V0: Trustworthy Run Identity

Goal:

> Make agent runs a first-class in-memory model without changing the user's visible workflow too much.

Scope:

| Capability | Detail |
| --- | --- |
| In-memory `AgentRunStore` | Tracks active and recent runs by pane/provider/context. |
| Provider lifecycle ingestion | Existing `*_activity` socket events create/update runs. |
| Transcript snippets | Existing `*_transcript` events attach to runs as events. |
| Completion attribution | Completion only closes the matching run, never all runs in a project. |
| Mission Control adapter | Current popover can still render from legacy activity/notifications while store is populated. |
| Tests | Store start/stop/transcript/completion behavior. |

Non-goals:

| Non-goal | Reason |
| --- | --- |
| Persistence | Avoid migration complexity until identity is stable. |
| Full transcript browser | Needs session mapping and file readers. |
| Verification UI | Requires run model first. |
| Inline replies/permissions | Provider control APIs are not normalized yet. |

Acceptance criteria:

| Criterion | Expected behavior |
| --- | --- |
| Multiple same-provider runs can coexist | Completing one does not complete the others. |
| Rows have a stable run identity | Future UI can use `AgentRun.id`, not notification ID. |
| Transcript events do not disappear immediately | Latest snippets are attached to the run. |
| Weak attribution is visible in model | Fallback runs do not claim exact pane confidence. |

Kill criteria:

> If V0 requires large rewrites to notifications or terminal rendering, stop and keep it as a sidecar store until the integration points are cleaner.

## Agent Store V1: Mission Control On Runs

Goal:

> Replace the popover's core data source with AgentRunStore so Agents is no longer notification-driven.

Scope:

| Capability | Detail |
| --- | --- |
| Popover reads runs | Mission Control rows are built from `AgentRunStore.runs`. |
| Notification fallback section | Detached provider events still appear, but separately. |
| Runtime and last update | Show elapsed runtime and freshness. |
| Grouping | Needs Attention, Running, Completed. |
| Row expansion | Show recent timeline snippets inline. |
| Exact navigation | Row navigation uses live pane first, then session/worktree fallback. |

Acceptance criteria:

| Criterion | Expected behavior |
| --- | --- |
| Agents is not a notification list | Rows represent runs even if no notification was emitted. |
| Completed rows stay inspectable | Completion does not erase run context. |
| Stale rows are honest | Closed/missing panes show stale or detached state. |
| Attention rows are first | Questions and permissions are always above passive completions. |

## Agent Store V2: Evidence And Verification

Goal:

> Make every completed run answer: what changed, did it pass, and should I trust it?

Scope:

| Capability | Detail |
| --- | --- |
| Changed files summary | Capture git diff stat at completion for the run's worktree. |
| Verification action | Run project-level checks from Agents. |
| Verification state | Pending, running, passed, failed, skipped. |
| Verification output | Store short failure output and link to terminal/log. |
| Review actions | Open VCS, changed files, transcript. |
| Evidence actions | Open changed files or their diff directly from expanded Mission Control evidence. |
| Provider session metadata | Attach session ID/path for Codex, Claude, and OpenCode. |

Verification defaults:

| Source | Command |
| --- | --- |
| Project config | Future `kaji project settings`. |
| Repo docs | Parse `AGENTS.md` recommended checks. |
| Swift package | `swift build && swift test`. |
| Fallback | No automatic verification, show `Verification pending`. |

Acceptance criteria:

| Criterion | Expected behavior |
| --- | --- |
| Completed run has evidence | User sees files changed and final summary. |
| Verification is one click | User can run checks without finding the right terminal. |
| Failures are actionable | Failed verification links to output and source pane. |
| Evidence is inspectable | The popover keeps evidence collapsed by default but can expand a run row to show file paths, statuses, stats, or attribution warnings. |

Attribution rule:

| Situation | Behavior |
| --- | --- |
| Provider reports session-specific changed files | Show exact files for that run. |
| Only one run is active in a worktree | Show git worktree snapshot with `snapshot` attribution. |
| Multiple runs overlap in the same worktree | Do not claim exact files; show `shared worktree` until provider-specific evidence exists. |
| Run uses a separate worktree | Show that worktree's files independently. |

This means two OpenCode agents on the same branch and same worktree cannot be separated exactly from git state alone. Kaji should either use provider session diffs when available or encourage isolated worktrees for exact per-agent evidence.

## Agent Store V3: Control Plane

Goal:

> Let users manage agent work from the popover instead of switching to terminals for every action.

Scope:

| Capability | Detail |
| --- | --- |
| Resume | Provider-native resume by session ID. |
| Follow-up prompt | Send a reply to the run's pane/session. |
| Permission broker | Approve/deny where provider hooks support it. |
| Stop/restart | Terminate or relaunch a run safely. |
| Worktree autopilot | Create isolated worktrees for new runs. |
| Recipes | Start common tasks from run templates. |
| Handoff summaries | Generate and store task summaries. |

Acceptance criteria:

| Criterion | Expected behavior |
| --- | --- |
| User can act without hunting | Jump, resume, verify, reply, and review are available in-row. |
| Permissions are safe | Auto-approval requires explicit policy and audit trail. |
| Worktree isolation is defaultable | Parallel agents do not collide by default. |

## Agent Store V4: Orchestration And Learning

Goal:

> Turn Kaji into a local operating system for multiple AI agents working as a team.

Scope:

| Capability | Detail |
| --- | --- |
| Multi-agent task queue | Queue tasks across providers and worktrees. |
| Dependency graph | Block tasks on other runs, tests, or review. |
| Agent quality metrics | Track success, failure, verification, runtime, and retries. |
| Cost and quota guardrails | Alert when provider limits or local resource thresholds are near. |
| Automatic PR prep | After verified runs, prepare commit/PR artifacts. |
| Team memory | Share local project gotchas and run outcomes. |

Acceptance criteria:

| Criterion | Expected behavior |
| --- | --- |
| Agents are orchestrated | Kaji can run independent tasks safely in parallel. |
| Learning improves routing | Provider and recipe recommendations reflect past outcomes. |
| Automation remains auditable | Every automatic action has a timeline event and rollback path. |

## Provider Integration Plan

| Provider | V0 | V1 | V2 | V3 |
| --- | --- | --- | --- | --- |
| Codex | Hook events, pane ID, cwd from JSONL. | Session ID/path mapping. | JSONL transcript and git diff stat. | `codex resume`, verification, stop/restart. |
| Claude Code | Hook events, pane ID, `transcript_path` where available. | Transcript path mapping. | JSONL transcript, tool/file extraction. | `claude --resume`, permission/question actions if supported. |
| OpenCode | Plugin lifecycle, pane ID, session messages. | Session/message/part mapping. | `session_diff`, message parts, verification. | `opencode --session`, plugin-mediated attention actions. |

## UI Evolution

### V0 UI

No major UI change. Populate store behind the scenes.

### V1 UI

```text
Agents

Needs Attention
  Claude Code     Permission requested       muxy / main

Running
  OpenCode        Fix tests                   muxy / feature-x     04:12
    TOOL  swift test --filter Ask
    TEXT  Found failing assertion in...

Completed
  Codex           Add transcript snippets     muxy / main          Verified pending
```

### V2 UI

Add row actions:

```text
Jump   Transcript   Files   Verify   Dismiss
```

### V3 UI

Add active controls:

```text
Reply   Resume   Approve   Deny   Stop   Restart
```

## Data Retention

| Data | V0 | V1 | V2+ |
| --- | --- | --- | --- |
| Run metadata | Memory only | Persist recent runs | Persist with retention limit. |
| Transcript snippets | Memory only | Persist last N snippets | Link to provider transcript files. |
| Full transcript | Provider files | Provider files | Optional normalized cache. |
| Verification output | None | None | Store bounded output logs. |
| Changed files | None | None | Store file paths and diff stat, not full diff by default. |

## Risks

| Risk | Mitigation |
| --- | --- |
| Wrong attribution | Require confidence levels and avoid active-project fallback for completions. |
| Provider schema drift | Keep provider parsers isolated and tested. |
| Privacy leakage | Do not sync transcript content; keep local. |
| UI bloat | Use progressive disclosure and grouped rows. |
| Automation mistakes | Verification and permission actions require explicit user intent first. |

## Immediate Next Step

Implement Agent Store V0 as a sidecar store:

1. Add `AgentRun`, `AgentRunEvent`, and `AgentRunStore`.
2. Mirror existing activity start/stop/transcript events into the store.
3. Keep the current Mission Control snapshot builder unchanged at first.
4. Add tests for multiple same-provider runs and exact-pane completion.
5. Migrate the popover to run-backed rows in V1 after V0 is stable.
