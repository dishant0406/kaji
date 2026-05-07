import Foundation

struct CodingAgentShimScript {
    let name: String
    let content: String

    static let all = [
        Self(name: "codex", realEnv: "DROID_REAL_CODEX", bridge: "codex"),
        Self(name: "claude", realEnv: "DROID_REAL_CLAUDE", bridge: "claude"),
        Self(name: "claude-code", realEnv: "DROID_REAL_CLAUDE_CODE", bridge: "claude"),
        Self(name: "opencode", realEnv: "DROID_REAL_OPENCODE", bridge: "opencode"),
        Self(name: "pi", realEnv: "DROID_REAL_PI", bridge: "pi"),
    ]

    private init(name: String, realEnv: String, bridge: String) {
        self.name = name
        content = Self.script(realEnv: realEnv, bridge: bridge)
    }

    private static func script(realEnv: String, bridge: String) -> String {
        """
        #!/bin/sh
        real="${\(realEnv):-}"
        if [ -z "$real" ] || [ ! -x "$real" ]; then
          echo "Droid could not find the real \(realEnv) executable." >&2
          exit 127
        fi
        droid_dir="${DROID_CODE_GRAPH_PROJECT_DIR:-}"
        case "\(bridge)" in
          claude)
            if [ -n "$droid_dir" ] && [ -d "$droid_dir" ]; then
              CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1 exec "$real" --add-dir "$droid_dir" "$@"
            fi
            ;;
          codex)
            if [ -n "$droid_dir" ] && [ -d "$droid_dir" ]; then
              exec "$real" --add-dir "$droid_dir" "$@"
            fi
            ;;
          opencode)
            if [ -n "${DROID_CODE_GRAPH_OPENCODE_CONFIG:-}" ] && [ -f "$DROID_CODE_GRAPH_OPENCODE_CONFIG" ]; then
              OPENCODE_CONFIG="$DROID_CODE_GRAPH_OPENCODE_CONFIG" exec "$real" "$@"
            fi
            ;;
          pi)
            if [ -n "${DROID_CODE_GRAPH_INSTRUCTIONS:-}" ] && [ -f "$DROID_CODE_GRAPH_INSTRUCTIONS" ]; then
              exec "$real" --append-system-prompt "$DROID_CODE_GRAPH_INSTRUCTIONS" "$@"
            fi
            ;;
        esac
        exec "$real" "$@"
        """
    }
}
