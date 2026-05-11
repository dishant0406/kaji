# Kaji Agentic Product Roadmap

## Product Direction

Kaji should become the **hands-off local command center for terminal-native AI work**.

The core promise:

> Start AI work from one place, let it run safely in the background, know exactly when it needs you, resume context instantly, and ship only after verification.

This is different from Cursor, Windsurf, Claude Code, Codex, or OpenCode because Kaji owns the local runtime layer: terminal panes, projects, worktrees, notifications, sessions, provider hooks, and native macOS UI.

## Market Signals

Research across Reddit, developer forums, and current AI-agent discussions shows repeated pain around AI coding agents moving from novelty to daily workflow infrastructure.

Signal quality:

| Signal | Quality | Notes |
| --- | --- | --- |
| Terminal chaos | Strong | Repeated across Claude Code, Codex, tmux, and terminal-agent discussions. |
| Context loss | Strong | Users repeatedly mention re-explaining project architecture and prior decisions. |
| Invisible agent state | Strong | Users do not know if an agent is running, blocked, waiting, or done. |
| Review fatigue | Strong | Developers shift from coding to constant supervision and verification. |
| Cost and quota opacity | Medium | Strong concern, but exact willingness-to-pay needs validation. |
| Multi-agent orchestration | Medium | Growing pattern, but risky before workflow basics are solid. |

## Core User Job

Primary job-to-be-done:

> When I have coding work to delegate, I want to launch the right AI agent in the right project and worktree with the right context, let it run without babysitting, and return only when there is a clear decision, result, or safe artifact to review.

Secondary jobs:

| Job | User Need |
| --- | --- |
| Remember where I left off | Persistent session history, handoffs, and resumable tasks. |
| Know what needs attention | A durable queue for permission requests, blockers, failures, and completions. |
| Avoid workspace damage | Safe worktree isolation and approval policies. |
| Run tasks in parallel | Project-aware, worktree-aware agent orchestration. |
| Trust the result | Verification gates, diff review, test summaries, and run timelines. |
| Reduce repeated prompting | Context capsules, recipes, and reusable skills. |

## Positioning

Current positioning:

> Kaji is a native macOS terminal workspace for developers using AI coding agents.

Stronger positioning:

> Kaji is the local command center for hands-off AI coding work: launch agents, isolate tasks, track progress, preserve context, and verify results without babysitting terminals.

Tagline options:

| Tagline | Angle |
| --- | --- |
| Stop babysitting AI terminals. | Pain-driven and memorable. |
| Your local command center for AI coding agents. | Clear and category-defining. |
| Delegate coding work without losing control. | Trust and safety. |
| Run agents like a team, not a pile of terminals. | Multi-agent workflow. |

## Opportunity Map

Outcome:

> Increase successful hands-off AI task completion.

Problems:

| Problem | Product Opportunity |
| --- | --- |
| Users lose track of running agents. | Agent Mission Control. |
| Users do not know when agents need attention. | Human Attention Queue. |
| Users lose context across sessions. | Context Capsules and Handoff Summaries. |
| Users do not trust completed work. | Verification Gate. |
| Users fear parallel agents damaging work. | Worktree Autopilot. |
| Users repeat setup and prompt patterns. | Task Recipes. |
| Users do not understand cost or quota impact. | Cost and Quota Guardrails. |

## Best Feature Bets

| Rank | Feature | Why It Matters | Evidence | Effort | Priority |
| --- | --- | --- | --- | --- | --- |
| 1 | Agent Mission Control | Solves invisible sessions and terminal chaos. | Strong | Medium | Now |
| 2 | Task Launcher With Recipes | Makes `Cmd+Shift+N` hands-off and discoverable. | Strong | Low-Medium | Now |
| 3 | Context Capsules | Reduces repeated prompting and context loss. | Strong | Medium | Now |
| 4 | Worktree Autopilot | Enables safe parallel agents. | Strong | Medium | Now |
| 5 | Human Attention Queue | Turns notifications into actionable states. | Strong | Medium | Now |
| 6 | Verification Gate | Reduces review fatigue and increases trust. | Strong | Medium-High | Next |
| 7 | Agent Run Timeline | Makes every run inspectable and resumable. | Strong | Medium | Next |
| 8 | Auto-Handoff Summaries | Preserves state between sessions and providers. | Strong | Low-Medium | Next |
| 9 | Cost and Quota Guardrails | Addresses hidden token, build, and deploy costs. | Medium | Medium | Next |
| 10 | Approval Broker | Reduces approval fatigue without unsafe automation. | Medium | High | Later |
| 11 | Multi-Agent Swarm Mode | Differentiated but risky before foundations exist. | Medium | High | Later |
| 12 | PR and Issue Automation | Strong hands-off story after trust gates exist. | Medium | High | Later |

## Now Roadmap

### 1. Agent Mission Control

A native dashboard for all active and recent AI sessions.

It should show:

| Field | Purpose |
| --- | --- |
| Provider | Codex, Claude Code, OpenCode, or Terminal. |
| Project and worktree | Gives the user instant location context. |
| Status | Running, waiting, permission requested, failed, completed, idle. |
| Runtime | Helps identify runaway or stalled tasks. |
| Last event | Shows what changed without opening the pane. |
| Task title | Derived from prompt, session title, or recipe. |

Core actions:

| Action | Result |
| --- | --- |
| Jump | Navigate to the pane or external activity. |
| Reply | Send a follow-up prompt. |
| Resume | Reopen previous provider history. |
| Stop | Safely terminate or mark inactive. |
| Review diff | Open changed files or VCS view. |
| Run verification | Execute configured checks. |

V1 acceptance criteria:

| Criterion | Expected Behavior |
| --- | --- |
| Active AI sessions are visible | User can see Codex, Claude, and OpenCode state from one place. |
| Waiting sessions are obvious | Permission requests and questions are visually distinct. |
| Navigation works | Clicking an item jumps to the right pane or related context. |
| External events are represented | Events without panes still appear as external activity entries. |
| State persists | Recent runs survive app restart. |

Kill criteria:

> If fewer than 30% of users with AI activity open Mission Control weekly after two weeks, redesign the entry point or collapse it into the existing sidebar.

### 2. Task Launcher With Recipes

Turn `Cmd+Shift+N` into a hands-off task launcher instead of a syntax-first prompt box.

Built-in recipes:

| Recipe | Default Intent |
| --- | --- |
| Fix failing tests | Run tests, inspect failures, patch, rerun. |
| Review current diff | Analyze staged and unstaged changes. |
| Explain this repo | Summarize architecture and workflows. |
| Continue previous session | Resume selected provider history. |
| Implement feature | Plan, implement, test. |
| Debug error | Use pasted logs or last command output. |
| Update docs | Patch docs after code changes. |
| Prepare commit | Summarize changes and suggest commit message. |

Each recipe can define:

| Setting | Example |
| --- | --- |
| Provider | Codex, Claude, OpenCode. |
| Skill | `copywriting`, `code-review`, `product-management`. |
| Session mode | Best match, new session, existing session. |
| Worktree mode | Current, new isolated worktree, selected worktree. |
| Prompt template | Reusable task framing. |
| Verification command | `swift test --filter Ask`. |
| Permission profile | Safe, normal, strict. |

V1 scope:

| Capability | Notes |
| --- | --- |
| `/task` or `:task:` selector | Makes recipes discoverable. |
| Save current Ask input as recipe | Converts power-user syntax into reusable UI. |
| Project-level defaults | Provider, skill, and verification command. |
| Local storage | `~/Library/Application Support/Kaji/ask-recipes.json`. |

### 3. Context Capsules

A provider-neutral context package Kaji can inject, reference, or summarize.

Sources:

| Source | Use |
| --- | --- |
| `AGENTS.md` | Project rules and agent instructions. |
| `CLAUDE.md` | Claude-specific project memory. |
| `.agents/skills` | Reusable workflows. |
| `docs/architecture.md` | System design context. |
| Build and test commands | Verification context. |
| Recent handoffs | Last known task state. |

Context capsule contents:

| Section | Purpose |
| --- | --- |
| Project summary | What this repo is. |
| Architecture map | Key components and boundaries. |
| Commands | Build, test, lint, release. |
| Rules | Coding style, safety, repo constraints. |
| Known gotchas | Past failures and edge cases. |
| Recent decisions | Why important changes were made. |

V1 scope:

| Capability | Notes |
| --- | --- |
| Preview context before sending | Avoid hidden prompt bloat. |
| `:ctx:` annotation | Include context capsule from Ask overlay. |
| Handoff save | Store short task summaries after runs. |
| Local-first | No remote upload, no hidden sync. |

### 4. Worktree Autopilot

Allow AI tasks to run in safe isolated worktrees.

Flow:

1. User enters a task.
2. Kaji suggests or auto-selects a new worktree.
3. Kaji creates branch and worktree.
4. Kaji launches selected provider inside that worktree.
5. Kaji tracks status, files, and verification.
6. Kaji offers merge, keep, or delete after completion.

V1 scope:

| Capability | Notes |
| --- | --- |
| `:wt:new` | Fast new-worktree routing. |
| Generated branch names | Based on task prompt. |
| Cleanup prompt | Keep, delete, or merge after task. |
| Mission Control integration | Worktree visible on every run. |

### 5. Human Attention Queue

A durable queue for everything requiring the user.

Attention item types:

| Type | Example Action |
| --- | --- |
| Permission requested | Approve, deny, jump. |
| Agent question | Reply inline. |
| Tests failed | Open failure summary. |
| Task completed | Review diff or verify. |
| Session stalled | Jump or stop. |
| Cost warning | Pause or continue. |
| Merge conflict | Open git view. |

V1 scope:

| Capability | Notes |
| --- | --- |
| Persistent inbox | Items stay until resolved. |
| Severity levels | Info, warning, blocker. |
| One-click jump | Navigate to the pane or run. |
| Inline reply | Send follow-up without hunting the tab. |

## Next Roadmap

### Verification Gate

Before a task is marked done, Kaji should run configured checks.

Examples:

| Project Type | Verification Command |
| --- | --- |
| Swift | `swift build && swift test` |
| Kaji | `swift build && swift test --filter Ask` |
| Node | `npm test` |
| Rust | `cargo test` |
| Custom | User-defined command. |

Output:

| Output | Purpose |
| --- | --- |
| Pass/fail | Clear completion state. |
| Failure summary | Fast follow-up context. |
| Suggested next prompt | Continue the loop safely. |
| Diff summary | Review support. |

### Agent Run Timeline

A durable local record of every agent run.

Timeline events:

| Event | Example |
| --- | --- |
| Prompt submitted | User asked Codex to fix tests. |
| Provider launched | Codex started in worktree. |
| Files touched | List of changed files. |
| Commands run | Build/test/lint commands. |
| Permission requested | Agent asked to run network command. |
| Notification emitted | Stop, question, failure. |
| Verification result | Passed or failed. |
| Follow-up prompt | User continued from result. |

### Auto-Handoff Summaries

At the end of a run, Kaji should help preserve useful context.

Summary fields:

| Field | Why It Matters |
| --- | --- |
| What changed | Avoid rereading the full transcript. |
| What failed | Preserve debugging state. |
| Next step | Make resume reliable. |
| Files touched | Review and navigation. |
| Commands run | Verification history. |
| Risks | Human review focus. |
| Resume prompt | One-click continuation. |

### Cost and Quota Guardrails

Approximate guardrails are valuable even without exact token accounting.

Signals:

| Signal | Risk Detected |
| --- | --- |
| Long runtime | Runaway task. |
| Repeated test loop | Agent stuck debugging. |
| High command count | Expensive task. |
| Build/deploy commands | Possible external cost. |
| Provider usage files | Quota tracking where available. |

## Later Roadmap

### Approval Broker

Centralized permission policy across providers.

Modes:

| Mode | Behavior |
| --- | --- |
| Safe auto-approve | Reads, tests, formatting, harmless inspection. |
| Ask first | Package installs, network, commits, migrations. |
| Block | Destructive git, credential access, production deploy. |

Build this only after Mission Control and Verification Gate are reliable.

### Multi-Agent Swarm Mode

A lead workflow that decomposes work across providers and worktrees.

Example flow:

1. Codex investigates.
2. Claude implements.
3. OpenCode reviews.
4. Kaji verifies.
5. User reviews final diff.

Do not build this first. It will amplify chaos unless dashboard, worktree isolation, and verification are solid.

### PR and Issue Automation

Hands-off issue-to-draft-PR flow.

Flow:

1. Pick GitHub issue.
2. Create worktree.
3. Launch provider.
4. Run verification.
5. Generate PR summary.
6. Open draft PR.

This is valuable after trust gates exist.

## Feature Backlog

High-confidence ideas:

| Idea | Purpose |
| --- | --- |
| Agent status badges in tab title | Make state visible without opening Mission Control. |
| Global “Waiting for you” shortcut | Jump directly to attention-needed work. |
| Send follow-up to selected agent | Reduce navigation friction. |
| Provider health check | Detect missing CLIs and broken configs. |
| Project onboarding checklist | Set build, test, context, and provider defaults. |
| Resume last failed task | Fast recovery from broken runs. |
| Open same task in another provider | Provider comparison and fallback. |
| Diff-ready state | Notify when files changed and output stopped. |
| Run review agent over current diff | Lightweight verification assist. |
| Cleanup worktree prompt | Avoid worktree clutter. |
| Searchable run archive | Find past prompts, outputs, and outcomes. |
| Quiet mode | Notify only on blockers and completions. |

Ambitious ideas:

| Idea | Purpose |
| --- | --- |
| Local task graph | Connect prompt, run, files, tests, commits. |
| Repo knowledge graph | Richer context capsules. |
| Provider router | Choose provider by task type. |
| Auto-create skills | Turn repeated successful prompts into reusable workflows. |
| Reliability score | Track provider success by project/task type. |
| Branch risk meter | Flag risky file changes and weak verification. |
| Visual replay | Reconstruct an agent run for review. |

## Metrics

| Metric | Formula | Why It Matters |
| --- | --- | --- |
| AI activation | Users launching any AI provider through Kaji / active users | Measures core adoption. |
| Hands-off completion | Runs completed or verified without manual terminal monitoring / AI runs | Measures product promise. |
| Attention precision | Attention items acted on within 5 minutes / attention items | Measures notification quality. |
| Resume success | Resumed sessions with follow-up or completion / resumed sessions | Measures history value. |
| Worktree adoption | AI runs in isolated worktrees / AI runs | Measures safety workflow adoption. |
| Verification adoption | AI runs with verification configured / AI runs | Measures trust workflow adoption. |
| Weekly retained projects | Projects with AI activity this week and last week | Measures durable usage. |

Guardrails:

| Guardrail | Why |
| --- | --- |
| Crash-free sessions | Agent orchestration cannot destabilize the terminal. |
| Terminal performance | Background tracking must not slow terminal rendering. |
| No UI-blocking scans | Large history folders must never freeze the app. |
| Safe config writes | Never edit provider config without explicit confirmation. |
| Destructive action protection | No unsafe git, delete, or deploy actions without approval. |

## Recommended 0.24 Theme

Release theme:

> Agent Mission Control

Scope:

| Capability | Included |
| --- | --- |
| Active agent dashboard | Yes |
| Attention queue | Yes |
| Task recipes | Yes |
| Context handoff V1 | Yes |
| Verification command V1 | Yes |
| Multi-agent swarm | No |
| Auto PR creation | No |
| Cloud sync | No |
| Remote execution | No |

Acceptance criteria:

| Criterion | Expected Behavior |
| --- | --- |
| Start from recipe | User can launch Codex, Claude, or OpenCode without syntax. |
| See all active agents | User can inspect every running or waiting AI session. |
| Jump to blocker | User can open a permission request or question in one action. |
| Resume with prompt | User can resume provider history with or without a prompt. |
| Verify result | User can run configured checks from the run item. |
| Preserve handoff | User can resume from a generated task summary. |

## Validation Plan

Dogfood tasks:

1. Fix a failing test.
2. Implement a small feature.
3. Debug a real app issue.
4. Update documentation after code changes.
5. Prepare a commit.
6. Build a release DMG.
7. Resume a previous provider session.
8. Run two agents in parallel worktrees.
9. Handle a permission request.
10. Verify and review an agent’s final diff.

Questions to answer during dogfooding:

| Question | Signal |
| --- | --- |
| When did I still manually check terminal output? | Mission Control gap. |
| What made me not trust the agent result? | Verification gap. |
| What context did I repeat? | Context Capsule gap. |
| Which notification was useful? | Attention Queue quality. |
| Which notification was noise? | Notification filtering. |
| When did worktree setup feel slow? | Worktree Autopilot UX. |

User interview questions:

1. How many AI coding sessions do you run per day?
2. How do you know which session needs attention?
3. What makes you switch from one provider to another?
4. How do you resume a previous task today?
5. How do you prevent agents from stepping on each other?
6. What do you do before trusting an agent’s work?
7. What notification do you wish you got sooner?
8. What notification annoys you?
9. What context do you repeat most often?
10. What is the last time an agent wasted your time?

## Final Recommendation

Do not build every advanced feature at once.

Build around one sharp promise:

> Kaji lets you delegate AI coding tasks locally and come back only when your attention matters.

The next product milestone should be **Agent Mission Control** because it turns the existing Ask overlay, provider hooks, worktrees, notifications, history, and skills into one coherent hands-off workflow.
