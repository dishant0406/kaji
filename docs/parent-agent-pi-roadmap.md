# Parent Agent And Pi Fork Roadmap

## Intent

Droid should become a native macOS command center where the user describes coding work once, then Droid plans, launches, supervises, verifies, and summarizes local AI-agent execution across projects and worktrees.

The parent agent is powered by a customized Pi fork, but Droid remains the authority for UI, projects, worktrees, panes, provider terminals, permissions, verification, and local state.

## Core Architecture

```text
Droid SwiftUI Parent Agent UI
        |
ParentAgentController.swift
        |
ParentAgentProcess.swift
        |
JSONL over stdin/stdout
        |
Forked Pi packages/droid-agent
        |
Pi runtime + Droid tool definitions
        |
Droid native APIs + terminal coding providers
```

No sockets for Droid-to-Pi communication. Droid launches Pi as a child process, writes JSONL requests to stdin, reads JSONL events from stdout, and treats stderr as logs only.

## Fork Strategy

- Fork `badlogic/pi-mono` into a Droid-controlled fork.
- Add `packages/droid-agent` for Droid-specific orchestration.
- Reuse Pi provider and agent-runtime packages where useful.
- Avoid Pi TUI as the main UI; Droid's UI is native SwiftUI.
- Bundle the built Pi engine into Droid app resources.
- Suggested local layout: `External/pi-mono/`, `Droid/Resources/pi/droid-agent.js`, `scripts/build-pi.sh`.

## Protocol Contract

- One JSON object per line.
- `stdout` is machine-readable protocol only.
- `stderr` is human-readable logs only.
- Every `tool_call` has an ID and exactly one `tool_result`.
- Droid can restart a crashed Pi process and mark active tasks recoverable.
- Pi must never assume a tool succeeded until Droid returns `ok: true`.

Message types: `user_prompt`, `task_event`, `tool_call`, `tool_result`, `agent_event`, `permission_decision`, `final_response`, `error`, `heartbeat`.

## Parent Task Model

`ParentAgentTask` sits above existing `AgentRun` records.

Fields: `id`, `prompt`, `status`, `projects`, `worktrees`, `permissionProfile`, `plan`, `childRunIDs`, `timeline`, `verification`, `finalSummary`.

Statuses: `draft`, `planning`, `waitingForUser`, `running`, `needsAttention`, `verifying`, `completed`, `failed`, `cancelled`, `stale`.

Core events: `task.created`, `task.planning`, `task.plan_ready`, `task.step_started`, `task.step_completed`, `task.step_failed`, `agent.spawned`, `agent.prompt_sent`, `agent.running`, `agent.waiting`, `agent.needs_attention`, `agent.permission_requested`, `agent.completed`, `agent.failed`, `files.changed`, `verification.started`, `verification.passed`, `verification.failed`, `handoff.written`.

## Droid Tools For Pi

V0 tools: `droid.list_projects`, `droid.get_active_context`, `droid.ask_user`.

V1 tools: `droid.spawn_agent`, `droid.send_prompt`, `droid.get_agent_status`, `droid.jump_to_agent`.

V2 tools: `droid.open_project`, `droid.select_project`, `droid.select_worktree`, `droid.open_terminal`, `droid.open_split`, `droid.stop_agent`, `droid.resume_agent`.

V3 tools: `droid.create_worktree`, `droid.get_changed_files`, `droid.open_diff`, `droid.run_verification`, `droid.read_context_capsule`, `droid.write_handoff`.

V4+ tools: `droid.assign_subtask`, `droid.merge_worktree`, `droid.prepare_commit`, `droid.create_pr`, `droid.install_provider_hooks`, `droid.manage_permission_policy`.

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

Goal: Prove Droid can own a forked Pi process and render parent-agent events natively.

Scope: add `ParentAgentProcess`, Swift JSONL message types, `ParentAgentHome`, in-memory `ParentAgentTaskStore`, simple Pi `packages/droid-agent` entrypoint, and support for `droid.list_projects`, `droid.get_active_context`, and `droid.ask_user`.

Acceptance criteria: Droid opens the parent screen on launch, submitting a prompt starts Pi if needed, Pi task events render in SwiftUI, Droid can answer Pi tool calls, and Pi crash or malformed JSON becomes a recoverable task error.

Status: Complete after V0 polish. The implementation also includes real Pi provider streaming, provider/model settings, OAuth connect for Anthropic, ChatGPT/Codex, and GitHub Copilot, manual OAuth paste fallback, `droid.ask_user`, and a new-task reset.

## V1: Spawn One Provider Agent

Goal: Let the parent agent launch a real terminal coding provider through Droid.

Scope: add `droid.spawn_agent` using existing `AskCommandDispatcher` and `AppState`, support Codex/Claude/OpenCode/terminal, attach child `AgentRun` IDs to parent tasks, forward relevant `AgentRunStore` events, and show child run cards in the parent UI.

Acceptance criteria: a parent prompt can open a provider tab and send a prompt, the parent UI shows provider/project/worktree/pane/status, attention and completion events appear under the task, and the user can jump to the child terminal.

## V2: Native Workspace Control

Goal: Let Pi control Droid workspace structure through safe native tools instead of terminal hacks.

Scope: add project selection, worktree selection, terminal tab creation, split creation, stop, resume, and jump controls; expose these as protocol tools; keep Droid authoritative for actual pane IDs and navigation.

Acceptance criteria: Pi can request tabs and splits, Droid opens them natively, all created panes are tracked, and invalid project/worktree requests fail safely with visible errors.

## V3: Worktree Safety And Verification

Goal: Make delegated work isolated and reviewable.

Scope: add `droid.create_worktree`, changed-file collection, diff opening, verification command execution, persisted parent tasks, and final result cards with verification state.

Acceptance criteria: parent tasks can create isolated worktrees, completed runs show changed files honestly, verification can run from the parent task, and parent tasks survive app restart.

## V4: Multi-Agent Task Plans

Goal: Let the parent Pi fork decompose work and run multiple child agents intentionally.

Scope: add structured plans with steps, dependencies, assigned providers, parallel child runs, per-step status, retry/stop controls, and parent-level attention aggregation.

Acceptance criteria: Pi can create a plan before execution, Droid can open split terminals for parallel agents, each child run is tied to a plan step, and the parent task pauses when user input is required.

## V5: Context Capsules And Handoffs

Goal: Reduce repeated prompting and preserve useful task memory.

Scope: generate context from `AGENTS.md`, architecture docs, project commands, Droid settings, recent handoffs, and task history; add context preview; add `droid.read_context_capsule` and `droid.write_handoff`.

Acceptance criteria: parent tasks can include project-specific context, users can preview and trim context, handoffs are saved after completion/cancellation, and later tasks can reuse handoffs.

## V6: Permission Broker

Goal: Make autonomous work practical without making it unsafe.

Scope: normalize provider questions and permission events into parent decisions, add approve/deny/rewrite controls, store permission audit trails, and support provider/project permission policies.

Acceptance criteria: provider permission requests surface in the parent task, user answers from the parent UI, decisions are stored, and dangerous operations always require explicit approval.

## V7: Review, Commit, And PR Preparation

Goal: Move from completed work to shippable work.

Scope: add parent-level diff summaries, optional second-provider review, `droid.prepare_commit`, explicit commit approval, explicit PR approval, and short PR summary generation.

Acceptance criteria: parent tasks produce review packets with summary/files/verification/risks, commit and PR actions require user intent, and VCS actions reuse Droid git surfaces where possible.

## V8: Multi-Project Orchestration

Goal: Support requests spanning multiple local projects.

Scope: add project detection from prompt and selected context, cross-project plans, per-project worktree policies, dependency ordering, and final summaries grouped by project.

Acceptance criteria: one prompt can launch work in multiple projects, each child run starts in the correct project/worktree, verification is grouped by project, and wrong-context launches are treated as critical bugs.

## V9: Autonomous Droid Mode

Goal: Enable long-running supervised autonomy for trusted workflows.

Scope: add saved task recipes, queued tasks, provider fallback, cost/quota guardrails, merge-back workflows, failure recovery, and resumable parent tasks.

Acceptance criteria: saved workflows can run with minimal input, approval gates still pause execution, failures produce recoverable next actions, and hard safety stops cannot be bypassed.

## V10: Local Agent Platform

Goal: Make Droid a platform for custom local agent workflows.

Scope: add user-defined Droid tools with strict permissions, shareable recipes, provider routing rules, local outcome analytics, and extension points for non-coding automations.

Acceptance criteria: advanced users can define workflows without editing Droid source, Droid measures outcomes such as verified completion and attention latency, and extensions cannot access unsafe capabilities without explicit grants.

## Metrics

- Task start success rate: parent prompts that create valid tasks.
- Agent launch success rate: child runs that attach to tracked panes.
- Attention latency: time from provider question to user response.
- Verified completion rate: completed parent tasks with passing verification.
- Wrong-context rate: child runs launched in the wrong project/worktree.
- Recovery rate: failed tasks that can be resumed or retried.

## Open Decisions

- Whether the Pi fork is a submodule, subtree, sibling checkout, or vendored source.
- Whether the bundled engine ships with Node or uses the user's Node runtime.
- Which Pi coding-agent pieces are reused versus bypassed.
- Which provider/model powers the parent agent by default.
- Whether parent-agent history should be encrypted at rest.

## Immediate Next Step

Build V0 only: process bridge, JSONL protocol, native parent screen, in-memory task store, and a minimal forked Pi `droid-agent` entrypoint that emits task events and requests simple Droid tools.
