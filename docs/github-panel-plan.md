# GitHub Panel Research and Implementation Plan

## Objective

Add a native GitHub side panel to Kaji that ships with a pinned GitHub CLI binary, supports GitHub.com and GitHub Enterprise hosts, and covers repository collaboration without leaving the active project or worktree.

The first complete product surface must include:

- Pull request discovery, review, inline comments, approvals, requested changes, checks, merge controls, and Kaji diff-viewer integration.
- Workflow discovery, manual dispatch, live run/job/step state, cancellation, reruns, deployment approvals, logs, and artifacts.
- Account and repository context that follow the active Kaji worktree.
- Clear expansion paths for issues, releases, projects, repository administration, search, secrets, variables, Codespaces, attestations, discussions, and newer `gh` capabilities.

## Current Kaji Foundation

- `MainWindow` already has a mutually exclusive attached side-panel system and a resizable VCS panel.
- `VCSTabState` owns local Git state plus a small branch-scoped PR summary.
- `GitRepositoryService` shells out to a user-installed `gh` for PR create, view, merge, close, account tokens, and default-branch lookup.
- `GitHubAccountService` already parses multi-account `gh auth status --json hosts` output and filters accounts by the origin remote host.
- The current PR model contains only URL, number, state, draft state, base branch, mergeability, merge-state status, and aggregate checks.
- The existing diff viewer supports working-tree and commit sources. Its comments are local AI-review notes, not GitHub review threads.
- `GitProcessRunner` is a batch runner with a 30-second timeout and cannot power long-lived workflow observation or incremental output.
- `NativeCommandRunner` demonstrates cancellable process streaming, but its unstructured string output is not suitable as the primary GitHub data layer.

## Product Boundary

Kaji should not reproduce the GitHub website screen for screen. It should expose the repository operations developers need while coding, reviewing, and shipping.

### Native Kaji Surfaces

| Area | Kaji functionality |
| --- | --- |
| Repository | Active host/account/repository, default branch, permissions, rate limit, open on GitHub |
| Pull requests | Lists and filters, details, timeline, commits, files, checks, reviewers, labels, assignees, milestones, draft/ready, update branch, close/reopen, merge/auto-merge |
| Reviews | Pending review, inline comments, multi-line comments, replies, edit/delete own comments, resolve/unresolve threads, approve, comment, request changes |
| Actions | Workflows, YAML, dispatch inputs, runs, jobs, steps, annotations, cancellation, rerun all/failed/job, deployment approval, logs, artifacts, caches |
| Issues | Lists, search, details, comments, create/edit, close/reopen, labels, assignees, milestones, lock, pin, transfer, development branch |
| Releases | Lists, details, create/edit/delete, upload/download assets, verification |
| Repository tools | Branch/ruleset visibility, deployments, environments, labels, milestones, fork/sync, repository status |
| Discovery | Cross-repository status, notifications, code/commit/issue/PR/repository search |
| Administration | Projects, variables, secrets metadata/update, Codespaces, Gists, attestations, SSH/GPG keys with elevated confirmation |
| Newer gh features | Discussions, agent tasks, skills, and supported preview features behind capability flags |

### Advanced CLI Escape Hatch

Keep aliases, completion, local `gh` config, extension management, raw `gh api`, and arbitrary preview commands out of the primary panel. Expose them through a GitHub command palette and an "Open gh Terminal" action using the bundled binary.

## Architecture Decision

Use a hybrid backend:

1. Bundle `gh` for deterministic availability, GitHub authentication, account switching, credential retrieval, and compatibility fallbacks.
2. Use native `URLSession` REST and GraphQL clients for panel data and mutations.
3. Use local `git` for complete PR diffs so Kaji keeps its existing high-performance diff renderer and context expansion.
4. Use short-lived process streaming only for operations where `gh` is the authoritative implementation or a useful fallback.

Do not add GitHub features to `GitRepositoryService` or `VCSTabState`. They are already broad and should remain focused on local repository state.

## Proposed Module Shape

Create `Kaji/Features/GitHub/` with files kept below 200 lines:

- `GitHubBinaryLocator`: override, bundled binary, development fallback, version validation.
- `GitHubCredentialBroker`: accounts, web login, token retrieval, scope refresh, logout, token redaction.
- `GitHubRepositoryResolver`: remote host, owner/repository identity, fork parent, active account.
- `GitHubRESTClient`: Codable requests, pagination, ETags, API version, rate limits, uploads, cancellation.
- `GitHubGraphQLClient`: typed queries and mutations for review threads, timeline data, Projects, and auto-merge.
- `GitHubWorkspaceStore`: per-`WorktreeKey` state, refresh policy, cancellation, selected section and filters.
- `GitHubPanelCoordinator`: visibility, width, active worktree store, navigation into workspace tabs.
- Feature folders for `PullRequests`, `Actions`, `Issues`, `Releases`, and `Repository` with separate models, services, stores, and views.

`MainWindow` should receive only the coordinator, a `.github` side-panel identity, the panel branch, and a top-bar toggle. The implementation must not further concentrate feature logic in `MainWindow`.

## Bundled GitHub CLI

- Add `scripts/fetch-github-cli.sh` with an exact version and official checksum verification.
- Download the architecture-specific macOS archive for `arm64` or `x86_64` and install it under `Kaji/Resources/GitHubCLI/`.
- Add the resource to `Package.swift`, an environment override for tests, release codesigning, and smoke verification of executable architecture and `gh --version`.
- Include the GitHub CLI license and third-party notices in the application resources.
- Prefer the bundled binary. Permit a system binary only as an explicit development override.
- Never log tokens, authorization headers, authenticated URLs, secret input, or raw environment dictionaries.

## Authentication and Permissions

- Reuse `gh auth login --web` so Kaji does not own an OAuth client secret or custom token persistence.
- Read accounts with `gh auth status --json hosts`; retrieve the selected token into memory only when constructing an API client.
- Bind credentials to an exact validated host. Never send a token to a host inferred from untrusted content.
- Support GitHub.com, `*.ghe.com`, and GitHub Enterprise Server API base paths.
- Model capabilities per account and repository. On a permission failure, explain the missing capability and offer a scoped `gh auth refresh` action.
- Treat destructive repository actions, secret changes, workflow cancellation, deployment approval, review submission, and merge as explicit confirmed commands.

## Pull Request Implementation

1. Load PR lists and detail/timeline data with GraphQL; use REST for checks, review comments, review submission, requested reviewers, and standard mutations.
2. Add `GitDiffSource.comparison(baseHash:headHash:title:)` and a focused compare-diff service.
3. Materialize PR base and head commits into Kaji-owned refs without checking out or modifying the user's worktree.
4. Fetch from the base/head repository URLs and fall back to a full PR patch when an object cannot be fetched directly.
5. Open PR files in the existing diff viewer with a `PullRequestReviewSession` attached to `DiffViewerTabState`.
6. Keep local AI review notes separate from GitHub review threads.
7. Map GitHub `line`, `side`, `start_line`, and `start_side` anchors onto existing old/new line indexes.
8. Render outdated threads in the file/timeline context even when they no longer map to the current diff.
9. Support a pending review containing multiple comments before submitting approve, comment, or request-changes state.
10. Connect failed checks to the corresponding workflow run in the Actions section.

## Actions Implementation

1. List workflows and state through REST, including disabled workflows.
2. Fetch workflow YAML for the selected ref and parse `workflow_dispatch.inputs` with a real YAML parser.
3. Build typed controls for boolean, choice, environment, and string inputs; validate required/default values before dispatch.
4. After dispatch returns, correlate the new run by workflow, ref, actor, event, and creation time while showing a locating state.
5. Poll the visible run for jobs and steps with cancellation, conditional requests, and backoff.
6. Show a live timeline for queued, in-progress, completed, skipped, cancelled, and failed jobs/steps plus annotations.
7. Support cancel, rerun all, rerun failed, rerun job, delete run, and approve/reject pending deployments where permitted.
8. Download and reveal artifacts, and expose cache listing/deletion in an advanced Actions view.
9. Download job/run logs when GitHub exposes them and retain a bounded local display buffer.

The public `gh run watch` behavior is progress polling, not guaranteed raw line-by-line log streaming. The production UX should promise live job/step state and annotations. Completed or available logs can refresh independently; experimental `gh run watch --compact` parsing should not be the source of truth.

## Remaining gh Coverage

Implement after PRs and Actions in this order:

1. Issues and notifications/status because they share comments, labels, assignees, milestones, and timeline infrastructure.
2. Releases, assets, deployments, environments, and repository rules because they directly support shipping.
3. Cross-repository search and organization/repository discovery.
4. Projects with GraphQL field-aware editing.
5. Variables and secrets with masked values and write-only secret entry.
6. Codespaces integrated with Kaji terminals, file transfer, ports, logs, rebuild, stop, and delete.
7. Gists, attestations, SSH/GPG keys, discussions, agent tasks, and skills.
8. Advanced command-palette wrappers for aliases, extensions, config, previews, and raw API requests.

## Delivery Phases

### Phase 0: Foundation

- Bundle, sign, locate, and smoke-test `gh`.
- Add repository identity, credentials, REST/GraphQL clients, pagination, rate-limit state, fixtures, and host validation.
- Add the GitHub top-bar button, attached panel shell, account/repository header, loading, empty, offline, auth, and permission states.

### Phase 1: Pull Requests

- PR lists, filters, detail, timeline, checks, metadata mutations, and browser fallback.
- Comparison diff source and safe base/head materialization.
- Remote review threads in the Kaji diff viewer.
- Pending review, comment, approve, request changes, resolve, edit, delete, merge, auto-merge, close, reopen, and update branch.
- Migrate the existing PR pill and create/merge/close operations onto the GitHub module.

### Phase 2: Actions

- Workflow list/detail/YAML/dispatch form.
- Run list/detail, live job/step timeline, annotations, cancel/rerun/delete, deployment approvals.
- Log and artifact download plus advanced cache controls.

### Phase 3: Collaboration and Shipping

- Issues, notifications/status, releases, deployments, environments, labels, milestones, rulesets, and search.

### Phase 4: Administration and Extended gh

- Projects, variables, secrets, Codespaces, Gists, attestations, keys, discussions, agent tasks, skills, and command-palette escape hatches.

## Validation Strategy

- Unit tests for repository parsing, host binding, account selection, permission mapping, pagination, rate-limit parsing, workflow input parsing, run correlation, PR anchor mapping, and comparison refs.
- `URLProtocol` fixture tests for every REST and GraphQL operation, including pagination, ETags, enterprise base URLs, errors, and cancellation.
- Store tests for stale-response rejection when project/worktree/account/PR/run selection changes.
- Process tests with a fake `gh` executable for auth, scope refresh, streaming, cancellation, and token-redaction guarantees.
- Diff tests for fork PRs, renamed/deleted/binary files, large diffs, force-pushes, outdated comments, multi-line anchors, and context expansion.
- UI state tests for unauthenticated, permission denied, offline, rate limited, empty repository, fork, archived repository, and enterprise-host cases.
- Release smoke tests that assert the bundled binary exists, is executable, matches the app architecture, is signed, reports the pinned version, and can run `gh auth status` without crashing.
- Optional gated integration tests against a dedicated repository for workflow dispatch, comments, review submission, reruns, artifacts, and cleanup.

## Completion Criteria

- No dependency on Homebrew or a user-installed `gh` in a release build.
- No token or secret leakage in logs, crash reports, process arguments, persisted state, or UI diagnostics.
- Switching projects, worktrees, repositories, hosts, or accounts cancels stale requests and cannot apply results to the wrong context.
- PR diffs never checkout branches or mutate the working tree.
- All destructive and externally visible mutations have confirmation, progress, success, and recoverable error states.
- PR review and workflow operations work on GitHub.com and have explicit capability handling for Enterprise hosts.
- Formatting, strict lint, build, full tests, release packaging, and release smoke checks pass.
