import Foundation

enum KajiCLICommandScriptFactory {
    static func script() -> String {
        """
        #!/bin/sh
        set -u
        if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
          printf '%s\n' 'Usage: kaji [path]'
          printf '%s\n' 'Open the current directory or path in Kaji.'
          exit 0
        fi
        if [ "${1:-}" = "--version" ]; then
          printf '%s\n' 'kaji'
          exit 0
        fi
        if [ "$#" -gt 1 ]; then
          printf '%s\n' 'kaji: expected zero or one path argument' >&2
          exit 64
        fi
        target="${1:-.}"
        if ! cd "$target" 2>/dev/null; then
          printf 'kaji: not a directory: %s\n' "$target" >&2
          exit 66
        fi
        resolved="$(pwd -P)"
        payload="$(printf '%s' "$resolved" | /usr/bin/base64 | /usr/bin/tr '+/' '-_' | /usr/bin/tr -d '=\n')"
        if [ -z "$payload" ]; then
          printf '%s\n' 'kaji: failed to encode path' >&2
          exit 70
        fi
        exec /usr/bin/open "kaji://open-project/$payload"
        """
    }
}
