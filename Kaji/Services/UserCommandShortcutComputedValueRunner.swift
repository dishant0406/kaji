import Foundation

enum UserCommandShortcutComputedValueRunner {
    static func run(command: String, workingDirectory: URL, timeout: TimeInterval = 5) async -> UserCommandShortcutComputedValueResult {
        await Task.detached(priority: .userInitiated) {
            runSync(command: command, workingDirectory: workingDirectory, timeout: timeout)
        }.value
    }

    private static func runSync(
        command: String,
        workingDirectory: URL,
        timeout: TimeInterval
    ) -> UserCommandShortcutComputedValueResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = workingDirectory

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return .failure(error.localizedDescription)
        }

        let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            process.waitUntilExit()
            return .failure("Computed variable timed out after \(Int(timeout)) seconds.")
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            return .failure(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .failure("Computed variable produced no output.") : .success(trimmed)
    }
}
