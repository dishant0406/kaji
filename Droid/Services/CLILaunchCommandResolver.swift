import Foundation

enum CLILaunchCommandResolver {
    static func resolve(_ launcher: CLILauncherConfiguration) -> String {
        let command = launcher.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty,
              let wrapperPath = wrapperPath(for: launcher.id),
              let executable = command.split(separator: " ", maxSplits: 1).first,
              executable == Substring(launcher.definition.defaultCommand)
        else {
            return command
        }

        let suffix = String(command.dropFirst(executable.count))
        return quoted(wrapperPath) + suffix
    }

    private static func wrapperPath(for id: String) -> String? {
        switch id {
        case "codex":
            DroidNotificationHooks.scriptPath(named: "droid-codex-wrapper", extension: "sh")
        case "claude":
            DroidNotificationHooks.scriptPath(named: "droid-claude-wrapper", extension: "sh")
        case "opencode":
            DroidNotificationHooks.scriptPath(named: "droid-opencode-wrapper", extension: "sh")
        default:
            nil
        }
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
