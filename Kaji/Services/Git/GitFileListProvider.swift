import Foundation

enum GitFileListProvider {
    static func filePaths(repoPath: String) async -> [String]? {
        await GitProcessRunner.offMain {
            filePathsSync(repoPath: repoPath)
        }
    }

    static func filePathsSync(repoPath: String, timeout: DispatchTimeInterval = .seconds(30)) -> [String]? {
        guard let gitPath = GitProcessRunner.resolveExecutable("git") else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = ["-C", repoPath, "ls-files", "-c", "-o", "--exclude-standard", "-z"]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        let output = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        _ = try? stderrPipe.fileHandleForReading.readToEnd()
        let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            process.waitUntilExit()
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        return GitIgnoreChecker.parseNullSeparated(output)
    }
}
