import Foundation

struct CodingAgentShimScript {
    let name: String
    let content: String

    static let all = [
        Self(name: "codex", realEnv: "KAJI_REAL_CODEX", bridge: "codex"),
        Self(name: "claude", realEnv: "KAJI_REAL_CLAUDE", bridge: "claude"),
        Self(name: "claude-code", realEnv: "KAJI_REAL_CLAUDE_CODE", bridge: "claude"),
        Self(name: "opencode", realEnv: "KAJI_REAL_OPENCODE", bridge: "opencode"),
        Self(name: "pi", realEnv: "KAJI_REAL_PI", bridge: "pi"),
    ]

    private init(name: String, realEnv: String, bridge: String) {
        self.name = name
        content = Self.script(executableName: name, realEnv: realEnv, bridge: bridge)
    }

    private static func script(executableName: String, realEnv: String, bridge: String) -> String {
        """
        #!/bin/sh
        real="${\(realEnv):-}"
        resolve_latest_nvm_real() {
          if ! command -v python3 >/dev/null 2>&1; then
            return
          fi
          KAJI_AGENT_EXECUTABLE="\(executableName)" python3 <<'PY'
        import os
        from pathlib import Path

        name = os.environ.get("KAJI_AGENT_EXECUTABLE", "")
        root = Path.home() / ".nvm" / "versions" / "node"
        if not name or not root.is_dir():
            raise SystemExit
        def version_key(path):
            return tuple(int(part) if part.isdigit() else 0 for part in path.name.lstrip("v").split("."))
        for version in sorted(root.iterdir(), key=version_key, reverse=True):
            candidate = version / "bin" / name
            if candidate.exists() and os.access(candidate, os.X_OK):
                print(candidate)
                break
        PY
        }
        case "$real" in
          ""|"${HOME:-}/.nvm/versions/node/"*)
            nvm_real="$(resolve_latest_nvm_real)"
            ;;
          *)
            nvm_real=""
            ;;
        esac
        if [ -n "$nvm_real" ] && [ -x "$nvm_real" ]; then
          real="$nvm_real"
        fi
        if [ -z "$real" ] || [ ! -x "$real" ]; then
          echo "Kaji could not find the real \(realEnv) executable." >&2
          exit 127
        fi
        kaji_dir="${KAJI_CODE_GRAPH_PROJECT_DIR:-}"
        kaji_root="${KAJI_CODE_GRAPH_ROOT_DIR:-}"
        resolve_kaji_graph() {
          if [ -n "$kaji_dir" ] && [ -d "$kaji_dir" ]; then
            return
          fi
          if ! command -v python3 >/dev/null 2>&1; then
            return
          fi
          eval "$(KAJI_CODE_GRAPH_CWD="$PWD" python3 <<'PY'
        import json
        import os
        import shlex
        from pathlib import Path

        cwd = Path(os.environ.get("KAJI_CODE_GRAPH_CWD", ".")).resolve()
        root = Path(os.environ.get("KAJI_CODE_GRAPH_ROOT_DIR") or Path.home() / ".kaji" / "extensions" / "kajicodegraph")
        try:
            state = json.loads((root / "state.json").read_text(encoding="utf-8"))
        except Exception:
            raise SystemExit
        if not state.get("isEnabled") or state.get("phase") != "installed":
            raise SystemExit
        best = None
        for graph in root.glob("projects/*/*/graphify-out/kaji-graph.json"):
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
            "KAJI_CODE_GRAPH_ROOT_DIR": str(root),
            "KAJI_CODE_GRAPH_PROJECT_DIR": str(directory),
            "KAJI_CODE_GRAPH_INSTRUCTIONS": str(directory / "instructions" / "AGENTS.md"),
            "KAJI_CODE_GRAPH_REPORT": str(directory / "graphify-out" / "GRAPH_REPORT.md"),
            "KAJI_CODE_GRAPH_JSON": str(directory / "graphify-out" / "kaji-graph.json"),
            "KAJI_CODE_GRAPH_OPENCODE_CONFIG": str(directory / "opencode.json"),
        }
        for key, value in values.items():
            print(f"{key}={shlex.quote(value)}")
        PY
        )"
          kaji_dir="${KAJI_CODE_GRAPH_PROJECT_DIR:-}"
          kaji_root="${KAJI_CODE_GRAPH_ROOT_DIR:-}"
        }
        ensure_kaji_bridges() {
          if [ -z "$kaji_dir" ] || [ ! -d "$kaji_dir" ]; then
            return
          fi
          if [ -n "${KAJI_CODE_GRAPH_INSTRUCTIONS:-}" ] && [ ! -f "$KAJI_CODE_GRAPH_INSTRUCTIONS" ]; then
            mkdir -p "$(dirname "$KAJI_CODE_GRAPH_INSTRUCTIONS")"
            {
              report_path="${KAJI_CODE_GRAPH_REPORT:-$kaji_dir/graphify-out/GRAPH_REPORT.md}"
              graph_path="${KAJI_CODE_GRAPH_JSON:-$kaji_dir/graphify-out/kaji-graph.json}"
              printf '%s\\n\\n' "# Kaji Project Instructions"
              printf '%s\\n\\n' "These instructions are owned by Kaji and apply only to agent sessions launched from Kaji."
              printf '%s\\n\\n' "## Kaji Code Graph"
              printf '%s%s%s\\n' "- If " "$report_path" " exists, read it before architecture or dependency questions."
              printf '%s%s%s\\n' "- If " "$graph_path" " exists, use it for exact graph nodes, edges, communities, or source files."
              printf '%s\\n' "- If either file is missing, continue with normal repo tools and mention Code Graph must be built first."
            } > "$KAJI_CODE_GRAPH_INSTRUCTIONS"
            unset report_path graph_path
            chmod 600 "$KAJI_CODE_GRAPH_INSTRUCTIONS" 2>/dev/null || true
          fi
          if [ -n "${KAJI_CODE_GRAPH_INSTRUCTIONS:-}" ] && [ -f "$KAJI_CODE_GRAPH_INSTRUCTIONS" ]; then
            if [ ! -f "$kaji_dir/AGENTS.md" ]; then
              {
                printf '%s\\n\\n' "# Kaji Project Instructions"
                printf '%s\\n' "Read instructions/AGENTS.md before answering architecture, dependency, or codebase navigation questions."
              } > "$kaji_dir/AGENTS.md"
            fi
            if [ ! -f "$kaji_dir/CLAUDE.md" ]; then
              printf '%s\\n\\n%s\\n' "# Kaji Project Instructions" "@instructions/AGENTS.md" > "$kaji_dir/CLAUDE.md"
            fi
          fi
        }
        resolve_kaji_graph
        ensure_kaji_bridges
        codex_model_config="model_instructions_file=\\"${KAJI_CODE_GRAPH_INSTRUCTIONS:-}\\""
        case "\(bridge)" in
          claude)
            if [ -n "$kaji_dir" ] && [ -d "$kaji_dir" ] && [ -n "$kaji_root" ] && [ -d "$kaji_root" ]; then
              CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1 exec "$real" --add-dir "$kaji_dir" --add-dir "$kaji_root" "$@"
            fi
            if [ -n "$kaji_dir" ] && [ -d "$kaji_dir" ]; then
              CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1 exec "$real" --add-dir "$kaji_dir" "$@"
            fi
            ;;
          codex)
            if [ -n "${KAJI_CODE_GRAPH_INSTRUCTIONS:-}" ] && [ -f "$KAJI_CODE_GRAPH_INSTRUCTIONS" ]; then
              if [ -n "$kaji_dir" ] && [ -d "$kaji_dir" ] && [ -n "$kaji_root" ] && [ -d "$kaji_root" ]; then
                exec "$real" -c "$codex_model_config" --add-dir "$kaji_dir" --add-dir "$kaji_root" "$@"
              fi
              if [ -n "$kaji_dir" ] && [ -d "$kaji_dir" ]; then
                exec "$real" -c "$codex_model_config" --add-dir "$kaji_dir" "$@"
              fi
              exec "$real" -c "$codex_model_config" "$@"
            fi
            if [ -n "$kaji_dir" ] && [ -d "$kaji_dir" ] && [ -n "$kaji_root" ] && [ -d "$kaji_root" ]; then
              exec "$real" --add-dir "$kaji_dir" --add-dir "$kaji_root" "$@"
            fi
            if [ -n "$kaji_dir" ] && [ -d "$kaji_dir" ]; then
              exec "$real" --add-dir "$kaji_dir" "$@"
            fi
            ;;
          opencode)
            if [ -n "${KAJI_CODE_GRAPH_OPENCODE_CONFIG:-}" ] && [ -f "$KAJI_CODE_GRAPH_OPENCODE_CONFIG" ]; then
              OPENCODE_CONFIG="$KAJI_CODE_GRAPH_OPENCODE_CONFIG" exec "$real" "$@"
            fi
            ;;
          pi)
            if [ -n "${KAJI_CODE_GRAPH_INSTRUCTIONS:-}" ] && [ -f "$KAJI_CODE_GRAPH_INSTRUCTIONS" ]; then
              exec "$real" --append-system-prompt "$KAJI_CODE_GRAPH_INSTRUCTIONS" "$@"
            fi
            ;;
        esac
        exec "$real" "$@"
        """
    }
}
