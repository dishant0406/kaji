# Droid


## Build & Run

```bash
scripts/setup.sh         # First-time setup (builds GhosttyKit.xcframework from Droid's Ghostty fork)
swift build              # Debug build
swift build -c release   # Release build
swift run Droid            # Run the app
```

Requires macOS 14+ and Swift 6.0+. No external dependency managers needed — everything is SPM-based.

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

- Droid is a macOS terminal multiplexer built with SwiftUI that uses [libghostty](https://github.com/dishant0406/ghostty) for terminal emulation and rendering via Metal.
- The architecture of the app is documented at `./docs/architecture.md` and must always be up to date.
- All the coding agents specific things are always inside `./Droid/Services/CodingAgents/` directory. The main logic of the app should not have any coding agent specific code. No hardcoded checks for coding agents should be present in the main logic of the app. If there are any coding agent specific code, it should be moved to `./Droid/Services/CodingAgents/` directory, under that specific coding agent's folder module.
- Make everything you make scalable. Such that there can be more coding agents in the future and the code should be able to accommodate that without any issues. For example, if you are adding a new coding agent, you should not have to change any code in the main logic of the app. You should only have to add a new module in `./Droid/Services/CodingAgents/` directory for that specific coding agent and implement the required functionality there.
- Always use the reusable Droid Components and Services whenever possible. If you need to add a new component or service, make sure to add it in a way that it can be reused in the future for other features or coding agents.

### Core Components

- **GhosttyService** (singleton) — Manages the single `ghostty_app_t` instance per process. Loads config from `~/.config/ghostty/config`, runs a 120fps tick timer, and handles clipboard callbacks.

- **GhosttyTerminalNSView** — AppKit `NSView` that hosts a ghostty surface (`ghostty_surface_t`). Handles all keyboard/mouse input routing to libghostty and manages the Metal rendering layer. This is bridged into SwiftUI via `GhosttyTerminalRepresentable`.

- **AppState** (@Observable) — Manages the mapping of projects → tabs → split pane trees. Tracks active project, active tab per project, and provides tab lifecycle operations (create, close, select).

- **ProjectStore** (@Observable) — Persists projects as JSON to `~/Library/Application Support/Droid/projects.json`. Projects are directories the user adds via NSOpenPanel.

## GhosttyKit Integration

`GhosttyKit/` is a C module wrapping `ghostty.h` — the libghostty API. The precompiled static library lives in `GhosttyKit.xcframework/` (gitignored, built via `scripts/setup.sh`).

Key libghostty types: `ghostty_app_t` (app), `ghostty_surface_t` (terminal surface), `ghostty_config_t` (configuration). Surfaces are created when terminal views move to a window and destroyed on removal.

The xcframework is built from [dishant0406/ghostty](https://github.com/dishant0406/ghostty) at `droid-performance-spike`. See [docs/building-ghostty.md](docs/building-ghostty.md) for details.

## Data Persistence

- **Projects:** `~/Library/Application Support/Droid/projects.json`
- **Ghostty config:** `~/.config/ghostty/config`
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
