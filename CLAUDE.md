# Kaji


## Build & Run

```bash
scripts/setup.sh         # First-time setup (builds TermyKit/libtermy from pinned Termy source)
swift build              # Debug build
swift build -c release   # Release build
swift run Kaji            # Run the app
```

Requires macOS 15+ and Swift 6.0+. No external dependency managers needed — everything is SPM-based.

## Linting & Formatting

Requires `swiftlint` and `swiftformat` (`brew install swiftlint swiftformat`).

```bash
scripts/checks.sh        # Run all checks (formatting, linting, build)
scripts/checks.sh --fix  # Auto-fix formatting and linting issues
swiftformat --lint .      # Check formatting only
swiftlint lint --strict   # Check linting only
```

Run `scripts/checks.sh --fix` after every task.

## Architecture

- Kaji is a macOS terminal multiplexer built with SwiftUI that uses libtermy from [termy](https://github.com/lassejlv/termy) for terminal emulation and AppKit rendering.
- The architecture of the app is documented at `./docs/architecture.md` and must always be up to date.
- All the coding agents specific things are always inside `./Kaji/Services/CodingAgents/` directory. The main logic of the app should not have any coding agent specific code. No hardcoded checks for coding agents should be present in the main logic of the app. If there are any coding agent specific code, it should be moved to `./Kaji/Services/CodingAgents/` directory, under that specific coding agent's folder module.
- Make everything you make scalable. Such that there can be more coding agents in the future and the code should be able to accommodate that without any issues. For example, if you are adding a new coding agent, you should not have to change any code in the main logic of the app. You should only have to add a new module in `./Kaji/Services/CodingAgents/` directory for that specific coding agent and implement the required functionality there.
- Always use the reusable Kaji Components and Services whenever possible. If you need to add a new component or service, make sure to add it in a way that it can be reused in the future for other features or coding agents.

### Core Components

- **TermyService** (singleton) — Manages Kaji-owned Termy render/config state. Loads the Kaji `termy.conf` snapshot, applies theme colors, and publishes terminal render defaults.

- **TermyTerminalNSView** — AppKit `NSView` that owns one libtermy terminal handle. It forwards keyboard, mouse, paste, search, resize, lifecycle, and process events through `TermyKit`.

- **AppState** (@Observable) — Manages the mapping of projects → tabs → split pane trees. Tracks active project, active tab per project, and provides tab lifecycle operations (create, close, select).

- **ProjectStore** (@Observable) — Persists projects as JSON to `~/Library/Application Support/Kaji/projects.json`. Projects are directories the user adds via NSOpenPanel.

## TermyKit Integration

`TermyKit/` is a C module wrapping `termy.h` and linking `TermyKit/lib/libtermy_ffi.dylib`, built by `scripts/setup.sh`.

Key libtermy types: `TermyFfiTerminal`, `TermyFfiConfig`, frame snapshots, events, encoded key/mouse input, and search batches. Terminal handles are created when terminal views move to a window and destroyed on removal.

The dylib is built from pinned Termy source with Kaji FFI extensions. See [docs/building-termy.md](docs/building-termy.md) for details.

## Data Persistence

- **Projects:** `~/Library/Application Support/Kaji/projects.json`
- **Termy config:** `~/Library/Application Support/Kaji/termy.conf`
- **Terminal state (tabs, splits):** in-memory only, lost on app close

## NSViewRepresentable Pitfalls

- Never return a cached/reused NSView from `makeNSView`. SwiftUI assumes it gets a fresh view and breaks silently when it doesn't (blank views, lost input).
- To keep an NSView alive across tab switches, keep the `NSViewRepresentable` mounted in the view tree (e.g. all tabs in a ZStack with `opacity(0)` + `allowsHitTesting(false)` for inactive ones) rather than conditionally removing it and relying on a registry cache.
- When debugging blank/empty NSView issues, first check whether the NSView is being re-mounted from a detached state — that's the most common cause.

## Top Level Rules

- Security first
- Native Only
- Maintainability
- Scalability
- Clean Code
- Clean Architecture
- Best Practices
- No Hacky Solutions

## Main Rules

- No commenting allowed in the codebase
- All code must be self-explanatory and cleanly structured
- Use early returns instead of nested conditionals
- Don't patch symptoms, fix root causes
- For every task, Consider how it will impact the architecture and code quality, not just the immediate problem
- Follow the existing code's pattern but offer refactors if they improve code quality and maintainability.
- Use logs for debugging.
- If the feature is testable, then you must write tests.
- Avoid long PR descriptions. It is for humans and keep it in 3 lines maximum.
- Upload screenshots or recordings for the PRs.


## Code Review

- Review the PRs/Code against the purpose of the PR/Issue/Asked. If you find unrelated issues to the PR during the review, Report them in a separate section.
- Apply review recommendations only after user's confirmation.
