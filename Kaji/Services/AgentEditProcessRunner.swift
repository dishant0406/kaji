import Foundation

struct AgentEditProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum AgentEditProcessError: Error {
    case launchFailed(String)
}

enum AgentEditProcessRunner {
    private static let queue = DispatchQueue(label: "app.kaji.agent-edit-runner", qos: .userInitiated)

    static func run(command: String, workingDirectory: String) async throws -> AgentEditProcessResult {
        let processBox = AgentEditProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    do {
                        try continuation.resume(returning: runSync(
                            command: command,
                            workingDirectory: workingDirectory,
                            processBox: processBox
                        ))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            processBox.cancel()
        }
    }

    private static func runSync(
        command: String,
        workingDirectory: String,
        processBox: AgentEditProcessBox
    ) throws -> AgentEditProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        processBox.set(process)

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            throw AgentEditProcessError.launchFailed(error.localizedDescription)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let timedOut = finished.wait(timeout: .now() + 60) == .timedOut
        if timedOut {
            process.terminate()
            process.waitUntilExit()
        }

        if processBox.isCancelled {
            throw CancellationError()
        }
        return AgentEditProcessResult(
            status: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}

private final class AgentEditProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private(set) var isCancelled = false

    func set(_ process: Process) {
        lock.withLock {
            self.process = process
            if isCancelled {
                process.terminate()
            }
        }
    }

    func cancel() {
        lock.withLock {
            isCancelled = true
            process?.terminate()
        }
    }
}
