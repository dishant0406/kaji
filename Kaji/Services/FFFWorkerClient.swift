import Darwin
import FFFWorkerProtocol
import Foundation

final class FFFWorkerClient: @unchecked Sendable {
    static let shared = FFFWorkerClient()

    private let queue = DispatchQueue(label: "app.kaji.fff-worker", qos: .userInitiated)
    private let workerURL: @Sendable () throws -> URL
    private let libraryURL: @Sendable () throws -> URL
    private let sleep: @Sendable (TimeInterval) -> Void
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var reader: FFFJSONLineReader?
    private var consecutiveFailures = 0

    init(
        workerURL: @escaping @Sendable () throws -> URL = FFFWorkerExecutableLocator.url,
        libraryURL: @escaping @Sendable () throws -> URL = { try FFFSearchBinaryStore.libraryURL() },
        sleep: @escaping @Sendable (TimeInterval) -> Void = Thread.sleep
    ) {
        self.workerURL = workerURL
        self.libraryURL = libraryURL
        self.sleep = sleep
    }

    func send(_ command: FFFWorkerCommand, timeout: TimeInterval = 20) async throws -> FFFWorkerResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    try continuation.resume(returning: sendSynchronously(command, timeout: timeout))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func remove(projectPaths: [String]) async {
        for path in Set(projectPaths) where !path.isEmpty {
            do {
                _ = try await send(.remove(projectPath: path), timeout: 10)
            } catch {
                queue.sync { invalidateProcess() }
                return
            }
        }
    }

    func shutdown() async {
        _ = try? await send(.shutdown, timeout: 5)
        queue.sync { invalidateProcess(terminate: false) }
    }

    private func sendSynchronously(_ command: FFFWorkerCommand, timeout: TimeInterval) throws -> FFFWorkerResult {
        do {
            try ensureProcess()
            let request = FFFWorkerRequest(command: command)
            let data = try FFFJSONLineCodec.encode(request, maximumBytes: fffWorkerMaximumRequestBytes)
            guard let input, var reader else { throw FFFSearchError.workerUnavailable }
            try input.write(contentsOf: data)
            let responseData = try reader.nextFrame(timeout: timeout)
            self.reader = reader
            let response = try JSONDecoder().decode(FFFWorkerResponse.self, from: responseData)
            guard response.id == request.id else { throw FFFSearchError.invalidWorkerResponse }
            if let failure = response.error {
                throw FFFSearchError.processFailed(failure.message)
            }
            guard let result = response.result else { throw FFFSearchError.invalidWorkerResponse }
            consecutiveFailures = 0
            return result
        } catch {
            consecutiveFailures = min(consecutiveFailures + 1, 6)
            invalidateProcess()
            if error is FFFSearchError { throw error }
            throw FFFSearchError.workerUnavailable
        }
    }

    private func ensureProcess() throws {
        if let process, process.isRunning { return }
        invalidateProcess(terminate: false)
        if consecutiveFailures > 0 {
            let delay = min(pow(2, Double(consecutiveFailures - 1)) * 0.1, 2)
            sleep(delay)
        }
        let executable = try workerURL()
        let library = try libraryURL()
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = executable
        process.arguments = ["--library", library.path]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        process.environment = TerminalEnvironmentPolicy.sanitizedEnvironment(from: ProcessInfo.processInfo.environment)
        try process.run()
        self.process = process
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading
        reader = FFFJSONLineReader(handle: outputPipe.fileHandleForReading, maximumBytes: fffWorkerMaximumResponseBytes)
    }

    private func invalidateProcess(terminate: Bool = true) {
        if terminate, let process, process.isRunning {
            process.terminate()
        }
        try? input?.close()
        try? output?.close()
        process = nil
        input = nil
        output = nil
        reader = nil
    }
}

enum FFFWorkerExecutableLocator {
    static func url() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["KAJI_FFF_WORKER_EXECUTABLE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty
        {
            return try validated(URL(fileURLWithPath: override))
        }
        var candidates: [URL] = []
        if let executable = Bundle.main.executableURL {
            candidates.append(executable.deletingLastPathComponent().appendingPathComponent("KajiFFFWorker"))
        }
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        candidates.append(current.appendingPathComponent(".build/debug/KajiFFFWorker"))
        candidates.append(current.appendingPathComponent(".build/arm64-apple-macosx/debug/KajiFFFWorker"))
        candidates.append(current.appendingPathComponent(".build/x86_64-apple-macosx/debug/KajiFFFWorker"))
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        throw FFFSearchError.workerUnavailable
    }

    private static func validated(_ url: URL) throws -> URL {
        guard url.isFileURL, FileManager.default.isExecutableFile(atPath: url.path) else {
            throw FFFSearchError.workerUnavailable
        }
        return url
    }
}
