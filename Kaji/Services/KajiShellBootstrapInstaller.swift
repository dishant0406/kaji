import Foundation

enum KajiShellBootstrapInstaller {
    static let zdotdirKey = "ZDOTDIR"
    static let userZdotdirKey = "KAJI_USER_ZDOTDIR"

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
            .appendingPathComponent(".kaji", isDirectory: true)
            .appendingPathComponent("shell", isDirectory: true)
            .appendingPathComponent("zsh", isDirectory: true)
    }

    private static func resolvedUserZdotdir(homeDirectory: String, userZdotdir: String?) -> String {
        let value = userZdotdir?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? homeDirectory : value
    }

    private static func script(for name: String) -> String {
        """
        _kaji_proxy_zdotdir="$ZDOTDIR"
        _kaji_user_zdotdir="${KAJI_USER_ZDOTDIR:-$HOME}"
        if [ -n "$_kaji_user_zdotdir" ] && [ "$_kaji_user_zdotdir" != "$_kaji_proxy_zdotdir" ]; then
          if [ -r "$_kaji_user_zdotdir/\(name)" ]; then
            export ZDOTDIR="$_kaji_user_zdotdir"
            . "$_kaji_user_zdotdir/\(name)"
            export ZDOTDIR="$_kaji_proxy_zdotdir"
          fi
        fi
        if [ -n "${KAJI_AGENT_SHIM_DIR:-}" ]; then
          _kaji_path=":$PATH:"
          case "$_kaji_path" in
            *":$KAJI_AGENT_SHIM_DIR:"*) PATH="$KAJI_AGENT_SHIM_DIR:${PATH//$KAJI_AGENT_SHIM_DIR:/}" ;;
            *) PATH="$KAJI_AGENT_SHIM_DIR:$PATH" ;;
          esac
          export PATH
          for _kaji_agent in codex claude claude-code opencode pi; do
            if [ -x "$KAJI_AGENT_SHIM_DIR/$_kaji_agent" ]; then
              eval "$_kaji_agent() { \\"$KAJI_AGENT_SHIM_DIR/$_kaji_agent\\" \\"\\$@\\"; }"
            fi
          done
          hash -r 2>/dev/null || true
          unset _kaji_path
        fi
        unset _kaji_agent _kaji_proxy_zdotdir _kaji_user_zdotdir
        """
    }
}
