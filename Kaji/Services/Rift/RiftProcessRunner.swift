import Darwin
import Foundation

struct RiftProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

actor RiftProcessRunner {
    private let binaryURL: URL
    private let timeout: TimeInterval

    init(binaryURL: URL, timeout: TimeInterval = 60) {
        self.binaryURL = binaryURL
        self.timeout = timeout
    }

    func run(arguments: [String], workingDirectory: String? = nil) async throws -> RiftProcessResult {
        let binaryURL = self.binaryURL
        let timeout = self.timeout
        return try await Task.detached(priority: .userInitiated) {
            try runProcess(binaryURL: binaryURL, arguments: arguments, workingDirectory: workingDirectory, timeout: timeout)
        }.value
    }
}

private func runProcess(
    binaryURL: URL,
    arguments: [String],
    workingDirectory: String?,
    timeout: TimeInterval
) throws -> RiftProcessResult {
    let process = Process()
    process.executableURL = binaryURL
    process.arguments = arguments
    if let workingDirectory {
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
    }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    let stdoutCollector = ProcessPipeCollector(pipe: stdoutPipe)
    let stderrCollector = ProcessPipeCollector(pipe: stderrPipe)
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    try process.run()
    let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
    if timedOut {
        process.terminate()
        if finished.wait(timeout: .now() + 1) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
    }

    stdoutCollector.stop()
    stderrCollector.stop()
    let stdout = String(data: stdoutCollector.data, encoding: .utf8) ?? ""
    let stderr = String(data: stderrCollector.data, encoding: .utf8) ?? ""
    if timedOut {
        return RiftProcessResult(status: -1, stdout: stdout, stderr: "Rift command timed out.")
    }
    return RiftProcessResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
}
