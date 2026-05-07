import Foundation

enum DroidShellBootstrapInstaller {
    static let zdotdirKey = "ZDOTDIR"
    static let userZdotdirKey = "DROID_USER_ZDOTDIR"

    static func install(
        homeDirectory: String = NSHomeDirectory(),
        userZdotdir: String? = ProcessInfo.processInfo.environment[zdotdirKey],
        fileManager: FileManager = .default
    ) -> [(key: String, value: String)] {
        let directory = self.directory(homeDirectory: homeDirectory)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            for name in [".zshenv", ".zprofile", ".zshrc", ".zlogin"] {
                let url = directory.appendingPathComponent(name)
                try Data(script(for: name).utf8).write(to: url, options: .atomic)
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
        } catch {
            return []
        }
        return [
            (key: zdotdirKey, value: directory.path),
            (key: userZdotdirKey, value: resolvedUserZdotdir(homeDirectory: homeDirectory, userZdotdir: userZdotdir)),
        ]
    }

    static func directory(homeDirectory: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(".droid", isDirectory: true)
            .appendingPathComponent("shell", isDirectory: true)
            .appendingPathComponent("zsh", isDirectory: true)
    }

    private static func resolvedUserZdotdir(homeDirectory: String, userZdotdir: String?) -> String {
        let value = userZdotdir?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? homeDirectory : value
    }

    private static func script(for name: String) -> String {
        """
        _droid_proxy_zdotdir="$ZDOTDIR"
        _droid_user_zdotdir="${DROID_USER_ZDOTDIR:-$HOME}"
        if [ -n "$_droid_user_zdotdir" ] && [ "$_droid_user_zdotdir" != "$_droid_proxy_zdotdir" ]; then
          if [ -r "$_droid_user_zdotdir/\(name)" ]; then
            export ZDOTDIR="$_droid_user_zdotdir"
            . "$_droid_user_zdotdir/\(name)"
            export ZDOTDIR="$_droid_proxy_zdotdir"
          fi
        fi
        if [ -n "${DROID_AGENT_SHIM_DIR:-}" ]; then
          _droid_path=":$PATH:"
          case "$_droid_path" in
            *":$DROID_AGENT_SHIM_DIR:"*) PATH="$DROID_AGENT_SHIM_DIR:${PATH//$DROID_AGENT_SHIM_DIR:/}" ;;
            *) PATH="$DROID_AGENT_SHIM_DIR:$PATH" ;;
          esac
          export PATH
          for _droid_agent in codex claude claude-code opencode pi; do
            if [ -x "$DROID_AGENT_SHIM_DIR/$_droid_agent" ]; then
              eval "$_droid_agent() { \\"$DROID_AGENT_SHIM_DIR/$_droid_agent\\" \\"\\$@\\"; }"
            fi
          done
          hash -r 2>/dev/null || true
          unset _droid_path
        fi
        unset _droid_agent _droid_proxy_zdotdir _droid_user_zdotdir
        """
    }
}
