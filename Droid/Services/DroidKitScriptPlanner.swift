import Foundation

enum DroidKitScriptPlanner {
    static func plan(script: DroidKitScript, project: Project?, worktree: Worktree?) throws -> DroidKitScriptRunPlan {
        try DroidKitDirectory.ensure()
        let runDirectory = DroidKitDirectory.runs.appendingPathComponent(runID(script), isDirectory: true)
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let scriptURL = runDirectory.appendingPathComponent("run.sh")
        let body = shellBody(for: script, runDirectory: runDirectory)
        try body.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        return DroidKitScriptRunPlan(
            script: script,
            workingDirectory: workingDirectory(for: script, project: project, worktree: worktree),
            runDirectory: runDirectory,
            scriptURL: scriptURL
        )
    }

    static func isRisky(_ script: DroidKitScript) -> Bool {
        let body = script.command.lowercased()
        return [
            "rm -rf",
            "sudo ",
            "git reset --hard",
            "git clean -fd",
            "push --force",
            "--force-with-lease",
            "chmod -r",
            "chown -r",
            "| sh",
            "| bash",
        ].contains { body.contains($0) }
    }

    private static func shellBody(for script: DroidKitScript, runDirectory: URL) -> String {
        let exitStatus = runDirectory.appendingPathComponent("exit.status").path
        let command = script.command.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "#!/bin/zsh",
            "set -o pipefail",
            command,
            "droid_status=$?",
            "printf '%s' \"$droid_status\" > \(ShellEscaper.escape(exitStatus))",
            "exit $droid_status",
            "",
        ].joined(separator: "\n")
    }

    private static func workingDirectory(for script: DroidKitScript, project: Project?, worktree: Worktree?) -> URL {
        switch script.directoryMode {
        case .activeWorktree:
            URL(fileURLWithPath: worktree?.path ?? project?.path ?? NSHomeDirectory())
        case .projectRoot:
            URL(fileURLWithPath: project?.path ?? worktree?.path ?? NSHomeDirectory())
        case .home:
            FileManager.default.homeDirectoryForCurrentUser
        }
    }

    private static func runID(_ script: DroidKitScript) -> String {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return "\(stamp)-\(script.slug)"
    }
}
