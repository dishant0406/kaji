# Parent Agent And Pi Fork Roadmap

## Intent

Kaji should become a native macOS command center where the user describes coding work once, then Kaji plans, launches, supervises, verifies, and summarizes local AI-agent execution across projects and worktrees.

The parent agent is powered by a Kaji-owned runtime that imports Pi through pinned npm packages, while Kaji remains the authority for UI, projects, worktrees, panes, provider terminals, permissions, verification, and local state.

## Core Architecture

```text
Kaji SwiftUI Parent Agent UI
        |
ParentAgentController.swift
        |
ParentAgentProcess.swift
        |
JSONL over stdin/stdout
        |
KajiParentAgentRuntime
        |
Pi npm packages + Kaji tool definitions
        |
Kaji native APIs + terminal coding providers
```

No sockets for Kaji-to-runtime communication. Kaji launches the parent runtime as a child process, writes JSONL requests to stdin, reads JSONL events from stdout, and treats stderr as logs only.

## Runtime Strategy

- Keep Kaji-specific orchestration in `KajiParentAgentRuntime`.
- Reuse Pi provider, OAuth, and agent-loop code through pinned `@earendil-works/pi-ai` and `@earendil-works/pi-agent-core` npm packages.
- Avoid Pi TUI as the main UI; Kaji's UI is native SwiftUI.
- Bundle the built Pi engine into Kaji app resources as `Kaji/Resources/pi/kaji-agent.mjs` and `Kaji/Resources/pi/oauth-login.mjs`.
- Build bundled runtime files with `scripts/build-parent-agent.sh`; release builds call this before Swift release packaging.
- Do not bundle Node.js. Kaji checks for user-installed Node 22.19+ and surfaces install guidance in Settings when it is missing.

## Protocol Contract

- One JSON object per line.
- `stdout` is machine-readable protocol only.
- `stderr` is human-readable logs only.
- Every `tool_call` has an ID and exactly one `tool_result`.
- Kaji can restart a crashed Pi process and mark active tasks recoverable.
- Pi must never assume a tool succeeded until Kaji returns `ok: true`.

Message types: `user_prompt`, `task_event`, `tool_call`, `tool_result`, `agent_event`, `permission_decision`, `final_response`, `error`, `heartbeat`.

## Parent Task Model

`ParentAgentTask` sits above existing `AgentRun` records.

Fields: `id`, `prompt`, `status`, `projects`, `worktrees`, `permissionProfile`, `plan`, `childRunIDs`, `timeline`, `verification`, `finalSummary`.

Statuses: `draft`, `planning`, `waitingForUser`, `running`, `needsAttention`, `verifying`, `completed`, `failed`, `cancelled`, `stale`.

Core events: `task.created`, `task.planning`, `task.plan_ready`, `task.step_started`, `task.step_completed`, `task.step_failed`, `agent.spawned`, `agent.prompt_sent`, `agent.running`, `agent.waiting`, `agent.needs_attention`, `agent.permission_requested`, `agent.completed`, `agent.failed`, `files.changed`, `verification.started`, `verification.passed`, `verification.failed`, `handoff.written`.

## Kaji Tools For Pi

V0 tools: `kaji.list_projects`, `kaji.get_active_context`, `kaji.ask_user`.

V1 tools: `kaji.spawn_agent`, `kaji.send_prompt`, `kaji.get_agent_status`, `kaji.observe_agents`, `kaji.sleep`, `kaji.wait_for_agents`, `kaji.jump_to_agent`.

V2 tools: `kaji.open_project`, `kaji.select_project`, `kaji.select_worktree`, `kaji.open_terminal`, `kaji.open_split`, `kaji.stop_agent`, `kaji.resume_agent`.

V3 tools: `kaji.create_worktree`, `kaji.get_changed_files`, `kaji.open_diff`, `kaji.run_verification`, `kaji.read_context_capsule`, `kaji.write_handoff`.

V4+ tools: `kaji.assign_subtask`, `kaji.merge_worktree`, `kaji.prepare_commit`, `kaji.create_pr`, `kaji.install_provider_hooks`, `kaji.manage_permission_policy`.

## Permission Profiles

`Safe`: read context, open tabs, create terminals, launch agents, and run non-destructive checks.

`Normal`: create worktrees, delegate edits to child agents, run project-local commands, and collect diffs.

`Autonomous`: run long multi-agent workflows and prepare commits, but still ask before push, destructive git, global config, or system-level changes.

Hard stops for all profiles:

- No force push without explicit approval.
- No destructive git reset/checkout without explicit approval.
- No secret exfiltration or credential display.
- No global shell/profile/config modification without approval.
- No committing or pushing unless explicitly requested.

## V0: Process Bridge And Native Shell

Goal: Prove Kaji can own a forked Pi process and render parent-agent events natively.

Scope: add `ParentAgentProcess`, Swift JSONL message types, `ParentAgentHome`, in-memory `ParentAgentTaskStore`, simple Kaji parent runtime entrypoint, and support for `kaji.list_projects`, `kaji.get_active_context`, and `kaji.ask_user`.

Acceptance criteria: Kaji opens the parent screen on launch, submitting a prompt starts Pi if needed, Pi task events render in SwiftUI, Kaji can answer Pi tool calls, and Pi crash or malformed JSON becomes a recoverable task error.

Status: Complete. The implementation includes the native shell, JSONL process bridge, in-memory task store, recoverable process errors, `kaji.list_projects`, `kaji.get_active_context`, `kaji.ask_user`, streamed assistant text, thinking streams, grouped tool events, and a new-thread reset.

Additional shipped scope: Parent Agent can be enabled or disabled in Settings, checks Node/runtime readiness, supports provider/model/thinking settings, OAuth connect for Anthropic, ChatGPT/Codex, and GitHub Copilot, reads API keys from environment or Pi auth, and uses Pi's real core agent runtime instead of a placeholder loop.

## V1: Spawn One Provider Agent

Goal: Let the parent agent launch a real terminal coding provider through Kaji.

Scope: add `kaji.spawn_agent` using existing `AskCommandDispatcher` and `AppState`, support Codex/Claude/OpenCode/terminal, attach child `AgentRun` IDs to parent tasks, forward relevant `AgentRunStore` events, and show child run cards in the parent UI.

Acceptance criteria: a parent prompt can open a provider tab and send a prompt, the parent UI shows provider/project/worktree/pane/status, attention and completion events appear under the task, and the user can jump to the child terminal.

Status: Complete for the first actionable provider-agent loop. The parent agent can call `kaji.spawn_agent`, `kaji.send_prompt`, `kaji.get_agent_status`, `kaji.observe_agents`, `kaji.sleep`, `kaji.wait_for_agents`, and `kaji.jump_to_agent`; Kaji opens provider splits through the native dispatcher, creates tracked run records, shows child-agent rows, captures feed/final output, and can navigate back to live panes.

Additional shipped scope: Kaji enforces spawn guardrails with one active worker per parent task by default, max child-run limits, duplicate-work blocking, and explicit opt-in for parallel workers. Workspace content remains mounted behind the Parent Agent screen so spawned terminals can run while the Parent Agent UI is visible. Child-agent provider/model selection is no longer hardcoded in Pi: Kaji exposes only enabled and installed coding agents, the parent must call `kaji.choose_agent` before `kaji.spawn_agent`, and spawn requests require the selected provider and model.

## V2: Native Workspace Control

Goal: Let Pi control Kaji workspace structure through safe native tools instead of terminal hacks.

Scope: add project selection, worktree selection, terminal tab creation, split creation, stop, resume, and jump controls; expose these as protocol tools; keep Kaji authoritative for actual pane IDs and navigation.

Acceptance criteria: Pi can request tabs and splits, Kaji opens them natively, all created panes are tracked, and invalid project/worktree requests fail safely with visible errors.

Status: Partially complete. `kaji.spawn_agent` already selects a project/worktree, opens command splits, and `kaji.jump_to_agent` navigates to tracked child panes. Remaining V2 work is exposing direct workspace-control tools such as `kaji.open_project`, `kaji.select_project`, `kaji.select_worktree`, `kaji.open_terminal`, `kaji.open_split`, `kaji.stop_agent`, and `kaji.resume_agent`.

## V3: Worktree Safety And Verification

Goal: Make delegated work isolated and reviewable.

Scope: add `kaji.create_worktree`, changed-file collection, diff opening, verification command execution, and persisted parent tasks.

Acceptance criteria: parent tasks can create isolated worktrees, completed runs show changed files honestly, verification can run from the parent task, and parent tasks survive app restart.

Status: Complete for the current parent-agent architecture. The parent agent can call `kaji.create_worktree`, `kaji.get_changed_files`, `kaji.open_diff`, and `kaji.run_verification`; Kaji creates/selects worktrees natively, snapshots changed files from Git, opens native diff tabs, and starts existing verification flows for tracked child runs. Parent tasks now persist across restarts, unfinished tasks are restored as stale instead of pretending they are still live, and completed turns keep the parent agent's final answer as the single visible summary.

## V4: Multi-Agent Task Plans

Goal: Let the parent Pi fork decompose work and run multiple child agents intentionally.

Scope: add structured plans with steps, dependencies, assigned providers, parallel child runs, per-step status, retry/stop controls, and parent-level attention aggregation.

Acceptance criteria: Pi can create a plan before execution, Kaji can open split terminals for parallel agents, each child run is tied to a plan step, and the parent task pauses when user input is required.

## V5: Context Capsules And Handoffs

Goal: Reduce repeated prompting and preserve useful task memory.

Scope: generate context from `AGENTS.md`, architecture docs, project commands, Kaji settings, recent handoffs, and task history; add context preview; add `kaji.read_context_capsule` and `kaji.write_handoff`.

Acceptance criteria: parent tasks can include project-specific context, users can preview and trim context, handoffs are saved after completion/cancellation, and later tasks can reuse handoffs.

## V6: Permission Broker

Goal: Make autonomous work practical without making it unsafe.

Scope: normalize provider questions and permission events into parent decisions, add approve/deny/rewrite controls, store permission audit trails, and support provider/project permission policies.

Acceptance criteria: provider permission requests surface in the parent task, user answers from the parent UI, decisions are stored, and dangerous operations always require explicit approval.

## V7: Review, Commit, And PR Preparation

Goal: Move from completed work to shippable work.

Scope: add parent-level diff summaries, optional second-provider review, `kaji.prepare_commit`, explicit commit approval, explicit PR approval, and short PR summary generation.

Acceptance criteria: parent tasks produce review packets with summary/files/verification/risks, commit and PR actions require user intent, and VCS actions reuse Kaji git surfaces where possible.

## V8: Multi-Project Orchestration

Goal: Support requests spanning multiple local projects.

Scope: add project detection from prompt and selected context, cross-project plans, per-project worktree policies, dependency ordering, and final summaries grouped by project.

Acceptance criteria: one prompt can launch work in multiple projects, each child run starts in the correct project/worktree, verification is grouped by project, and wrong-context launches are treated as critical bugs.

## V9: Autonomous Kaji Mode

Goal: Enable long-running supervised autonomy for trusted workflows.

Scope: add saved task recipes, queued tasks, provider fallback, cost/quota guardrails, merge-back workflows, failure recovery, and resumable parent tasks.

Acceptance criteria: saved workflows can run with minimal input, approval gates still pause execution, failures produce recoverable next actions, and hard safety stops cannot be bypassed.

## V10: Local Agent Platform

Goal: Make Kaji a platform for custom local agent workflows.

Scope: add user-defined Kaji tools with strict permissions, shareable recipes, provider routing rules, local outcome analytics, and extension points for non-coding automations.

Acceptance criteria: advanced users can define workflows without editing Kaji source, Kaji measures outcomes such as verified completion and attention latency, and extensions cannot access unsafe capabilities without explicit grants.

## Metrics

- Task start success rate: parent prompts that create valid tasks.
- Agent launch success rate: child runs that attach to tracked panes.
- Attention latency: time from provider question to user response.
- Verified completion rate: completed parent tasks with passing verification.
- Wrong-context rate: child runs launched in the wrong project/worktree.
- Recovery rate: failed tasks that can be resumed or retried.

## Open Decisions

- Whether Parent Agent history should be persisted and whether it should be encrypted at rest.
- Which V2 workspace tools should be exposed first versus kept internal behind `kaji.spawn_agent`.
- Which provider/model powers the parent agent by default.
- How much of Pi's full coding-agent application layer should be adopted later versus continuing to use Pi core with Kaji-native tools.

## Immediate Next Step

Finish V2 workspace-control basics: expose direct project/worktree selection and terminal/split opening tools through the JSONL protocol, keep Kaji authoritative for pane IDs, and fail invalid workspace requests safely with visible parent-agent errors.
