import Foundation

struct GitProcessResult {
    let status: Int32
    let stdout: String
    let stdoutData: Data
    let stderr: String
    let truncated: Bool
}

enum GitProcessError: Error {
    case launchFailed(String)
}

enum GitProcessRunner {
    private struct ProcessInvocation {
        let executable: String
        let arguments: [String]
        let workingDirectory: String?
        let environment: [String: String]?
        let lineLimit: Int?
        let signpostName: StaticString
    }

    private static let queue = DispatchQueue(
        label: "app.kaji.git-runner",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private static let searchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    static func resolveExecutable(_ name: String) -> String? {
        for directory in searchPaths {
            let path = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    static func runGit(
        repoPath: String,
        arguments: [String],
        lineLimit: Int? = nil
    ) async throws -> GitProcessResult {
        let fullArgs = ["git", "-C", repoPath] + arguments
        return try await dispatch {
            try runProcessSync(.init(
                executable: "/usr/bin/env",
                arguments: fullArgs,
                workingDirectory: nil,
                environment: nil,
                lineLimit: lineLimit,
                signpostName: "git"
            ))
        }
    }

    static func runCommand(
        executable: String,
        arguments: [String],
        workingDirectory: String,
        environment: [String: String]? = nil
    ) async throws -> GitProcessResult {
        try await dispatch {
            try runProcessSync(.init(
                executable: executable,
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: environment,
                lineLimit: nil,
                signpostName: "command"
            ))
        }
    }

    private static func dispatch(
        _ work: @escaping @Sendable () throws -> GitProcessResult
    ) async throws -> GitProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let result = try work()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: work())
            }
        }
    }

    static func offMainThrowing<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try continuation.resume(returning: work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runProcessSync(_ invocation: ProcessInvocation) throws -> GitProcessResult {
        let signpostID = GitSignpost.begin(invocation.signpostName, invocation.arguments.prefix(3).joined(separator: " "))
        defer { GitSignpost.end(invocation.signpostName, signpostID) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        if let environment = invocation.environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        if let workingDirectory = invocation.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            throw GitProcessError.launchFailed(error.localizedDescription)
        }

        let stdoutData: Data = if let lineLimit = invocation.lineLimit {
            try readWithLineLimit(handle: stdoutPipe.fileHandleForReading, process: process, lineLimit: lineLimit)
        } else {
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let timedOut = finished.wait(timeout: .now() + 30) == .timedOut
        if timedOut {
            process.terminate()
            process.waitUntilExit()
        }

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        let truncated = timedOut || process.terminationReason == .uncaughtSignal
        return GitProcessResult(
            status: process.terminationStatus,
            stdout: stdout,
            stdoutData: stdoutData,
            stderr: stderr,
            truncated: truncated
        )
    }

    private static func readWithLineLimit(
        handle: FileHandle,
        process: Process,
        lineLimit: Int
    ) throws -> Data {
        var collected = Data()
        var currentLineCount = 0
        let chunkSize = 65536

        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty {
                return collected
            }

            collected.append(chunk)
            currentLineCount += chunk.reduce(into: 0) { count, byte in
                if byte == 0x0A { count += 1 }
            }

            if currentLineCount >= lineLimit {
                process.terminate()
                return collected
            }
        }
    }
}
