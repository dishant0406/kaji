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
        droid_root="${DROID_CODE_GRAPH_ROOT_DIR:-}"
        resolve_droid_graph() {
          if [ -n "$droid_dir" ] && [ -d "$droid_dir" ]; then
            return
          fi
          if ! command -v python3 >/dev/null 2>&1; then
            return
          fi
          eval "$(DROID_CODE_GRAPH_CWD="$PWD" python3 <<'PY'
        import json
        import os
        import shlex
        from pathlib import Path

        cwd = Path(os.environ.get("DROID_CODE_GRAPH_CWD", ".")).resolve()
        root = Path(os.environ.get("DROID_CODE_GRAPH_ROOT_DIR") or Path.home() / ".droid" / "extensions" / "droidcodegraph")
        best = None
        for graph in root.glob("projects/*/*/graphify-out/droid-graph.json"):
            try:
                data = json.loads(graph.read_text(encoding="utf-8"))
                project = Path(data.get("projectPath") or "").resolve()
            except Exception:
                continue
            if cwd == project or project in cwd.parents:
                if best is None or len(str(project)) > len(str(best[0])):
                    best = (project, graph.parents[1])
        if best is None:
            raise SystemExit
        directory = best[1]
        values = {
            "DROID_CODE_GRAPH_ROOT_DIR": str(root),
            "DROID_CODE_GRAPH_PROJECT_DIR": str(directory),
            "DROID_CODE_GRAPH_INSTRUCTIONS": str(directory / "instructions" / "AGENTS.md"),
            "DROID_CODE_GRAPH_REPORT": str(directory / "graphify-out" / "GRAPH_REPORT.md"),
            "DROID_CODE_GRAPH_JSON": str(directory / "graphify-out" / "droid-graph.json"),
            "DROID_CODE_GRAPH_OPENCODE_CONFIG": str(directory / "opencode.json"),
        }
        for key, value in values.items():
            print(f"{key}={shlex.quote(value)}")
        PY
        )"
          droid_dir="${DROID_CODE_GRAPH_PROJECT_DIR:-}"
          droid_root="${DROID_CODE_GRAPH_ROOT_DIR:-}"
        }
        ensure_droid_bridges() {
          if [ -z "$droid_dir" ] || [ ! -d "$droid_dir" ]; then
            return
          fi
          if [ -n "${DROID_CODE_GRAPH_INSTRUCTIONS:-}" ] && [ ! -f "$DROID_CODE_GRAPH_INSTRUCTIONS" ]; then
            mkdir -p "$(dirname "$DROID_CODE_GRAPH_INSTRUCTIONS")"
            {
              report_path="${DROID_CODE_GRAPH_REPORT:-$droid_dir/graphify-out/GRAPH_REPORT.md}"
              graph_path="${DROID_CODE_GRAPH_JSON:-$droid_dir/graphify-out/droid-graph.json}"
              printf '%s\\n\\n' "# Droid Project Instructions"
              printf '%s\\n\\n' "These instructions are owned by Droid and apply only to agent sessions launched from Droid."
              printf '%s\\n\\n' "## Droid Code Graph"
              printf '%s%s%s\\n' "- Read " "$report_path" " before answering architecture, dependency, or codebase navigation questions."
              printf '%s%s%s\\n' "- Use " "$graph_path" " for exact graph nodes, edges, communities, or source files."
            } > "$DROID_CODE_GRAPH_INSTRUCTIONS"
            unset report_path graph_path
            chmod 600 "$DROID_CODE_GRAPH_INSTRUCTIONS" 2>/dev/null || true
          fi
          if [ -n "${DROID_CODE_GRAPH_INSTRUCTIONS:-}" ] && [ -f "$DROID_CODE_GRAPH_INSTRUCTIONS" ]; then
            if [ ! -f "$droid_dir/AGENTS.md" ]; then
              {
                printf '%s\\n\\n' "# Droid Project Instructions"
                printf '%s\\n' "Read instructions/AGENTS.md before answering architecture, dependency, or codebase navigation questions."
              } > "$droid_dir/AGENTS.md"
            fi
            if [ ! -f "$droid_dir/CLAUDE.md" ]; then
              printf '%s\\n\\n%s\\n' "# Droid Project Instructions" "@instructions/AGENTS.md" > "$droid_dir/CLAUDE.md"
            fi
          fi
        }
        resolve_droid_graph
        ensure_droid_bridges
        codex_model_config="model_instructions_file=\\"${DROID_CODE_GRAPH_INSTRUCTIONS:-}\\""
        case "\(bridge)" in
          claude)
            if [ -n "$droid_dir" ] && [ -d "$droid_dir" ] && [ -n "$droid_root" ] && [ -d "$droid_root" ]; then
              CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1 exec "$real" --add-dir "$droid_dir" --add-dir "$droid_root" "$@"
            fi
            if [ -n "$droid_dir" ] && [ -d "$droid_dir" ]; then
              CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1 exec "$real" --add-dir "$droid_dir" "$@"
            fi
            ;;
          codex)
            if [ -n "${DROID_CODE_GRAPH_INSTRUCTIONS:-}" ] && [ -f "$DROID_CODE_GRAPH_INSTRUCTIONS" ]; then
              if [ -n "$droid_dir" ] && [ -d "$droid_dir" ] && [ -n "$droid_root" ] && [ -d "$droid_root" ]; then
                exec "$real" -c "$codex_model_config" --add-dir "$droid_dir" --add-dir "$droid_root" "$@"
              fi
              if [ -n "$droid_dir" ] && [ -d "$droid_dir" ]; then
                exec "$real" -c "$codex_model_config" --add-dir "$droid_dir" "$@"
              fi
              exec "$real" -c "$codex_model_config" "$@"
            fi
            if [ -n "$droid_dir" ] && [ -d "$droid_dir" ] && [ -n "$droid_root" ] && [ -d "$droid_root" ]; then
              exec "$real" --add-dir "$droid_dir" --add-dir "$droid_root" "$@"
            fi
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
