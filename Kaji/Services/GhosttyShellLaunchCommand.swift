import Foundation

enum GhosttyShellLaunchCommand {
    static func interactiveShell(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let shell = userShell(environment: environment)
        let escapedShell = ShellEscaper.escape(shell)
        let name = URL(fileURLWithPath: shell).lastPathComponent
        if name == "zsh" || name == "bash" {
            return "\(escapedShell) -l"
        }
        return escapedShell
    }

    static func startupCommand(
        _ command: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let shell = ShellEscaper.escape(userShell(environment: environment))
        let escaped = command.replacingOccurrences(of: "'", with: "'\\''")
        return "\(shell) -l -i -c '\(escaped)'"
    }

    static func userShell(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let shell = environment["SHELL"], !shell.isEmpty {
            return shell
        }
        guard let pw = getpwuid(getuid()), let shellPtr = pw.pointee.pw_shell else {
            return "/bin/zsh"
        }
        return String(cString: shellPtr)
    }
}
