import ClosedLidCore
import Darwin
import Foundation

protocol ClosedLidStandardSessionManaging: AnyObject, Sendable {
    var onUnexpectedExit: (@Sendable () -> Void)? { get set }
    func probeCapability() async -> ClosedLidSelectorProbeResult
    func arm() async throws -> ClosedLidStandardSessionEvidence
    func disarm() async throws
    func status() async throws -> ClosedLidGuardResponse
    func heartbeat() async throws -> ClosedLidStandardSessionEvidence
    func shutdown() async
    func directRestore() -> kern_return_t
}

enum ClosedLidStandardGuardError: Error, Equatable {
    case unavailable
    case invalidResponse
    case selectorFailure(kern_return_t)
}

final class ClosedLidStandardGuardClient: ClosedLidStandardSessionManaging, @unchecked Sendable {
    static let shared = ClosedLidStandardGuardClient()

    private let queue = DispatchQueue(label: "app.kaji.closed-lid-guard", qos: .userInitiated)
    private let executableURL: @Sendable () throws -> URL
    private let selectorDriver: any ClosedLidSelectorDriving
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var reader: ClosedLidJSONLineReader?
    private var expectedExit = false
    private var restartCount = 0
    var onUnexpectedExit: (@Sendable () -> Void)?

    init(
        executableURL: @escaping @Sendable () throws -> URL = ClosedLidGuardExecutableLocator.url,
        selectorDriver: any ClosedLidSelectorDriving = IOPMRootDomainClosedLidSelectorDriver()
    ) {
        self.executableURL = executableURL
        self.selectorDriver = selectorDriver
    }

    func probeCapability() async -> ClosedLidSelectorProbeResult {
        await perform { ClosedLidSelectorCapabilityProbe.run(driver: self.selectorDriver) }
    }

    func arm() async throws -> ClosedLidStandardSessionEvidence {
        try await performThrowing {
            var lastError: Error = ClosedLidStandardGuardError.unavailable
            for attempt in 0 ... 1 {
                do {
                    let response = try self.sendSynchronously(.arm, timeout: 3)
                    guard response.state == .armed, response.selectorResult == KERN_SUCCESS,
                          let evidence = response.evidence
                    else { throw ClosedLidStandardGuardError.selectorFailure(response.selectorResult) }
                    self.restartCount = 0
                    return evidence
                } catch {
                    lastError = error
                    self.invalidateProcess()
                    _ = self.selectorDriver.setEnabled(false)
                    if attempt == 0 {
                        continue
                    }
                }
            }
            throw lastError
        }
    }

    func disarm() async throws {
        try await performThrowing {
            defer { self.invalidateProcess(terminate: false) }
            let response = try self.sendSynchronously(.disarm, timeout: 3)
            guard response.state == .disarmed, response.selectorResult == KERN_SUCCESS else {
                _ = self.selectorDriver.setEnabled(false)
                throw ClosedLidStandardGuardError.selectorFailure(response.selectorResult)
            }
        }
    }

    func status() async throws -> ClosedLidGuardResponse {
        try await performThrowing { try self.sendSynchronously(.status, timeout: 2) }
    }

    func heartbeat() async throws -> ClosedLidStandardSessionEvidence {
        try await performThrowing {
            let response = try self.sendSynchronously(.heartbeat, timeout: 2)
            guard response.state == .armed, response.selectorResult == KERN_SUCCESS,
                  let evidence = response.evidence
            else { throw ClosedLidStandardGuardError.invalidResponse }
            return evidence
        }
    }

    func shutdown() async {
        await perform {
            self.expectedExit = true
            _ = try? self.sendSynchronously(.shutdown, timeout: 2)
            self.invalidateProcess(terminate: false)
            _ = self.selectorDriver.setEnabled(false)
        }
    }

    func directRestore() -> kern_return_t {
        queue.sync { selectorDriver.setEnabled(false) }
    }

    private func sendSynchronously(
        _ command: ClosedLidGuardCommand,
        timeout: TimeInterval
    ) throws -> ClosedLidGuardResponse {
        try ensureProcess()
        let request = ClosedLidGuardRequest(command: command)
        guard let input, var reader else { throw ClosedLidStandardGuardError.unavailable }
        do {
            try input.write(contentsOf: ClosedLidJSONLineCodec.encode(request))
            let data = try reader.nextFrame(timeout: timeout)
            self.reader = reader
            let response = try JSONDecoder().decode(ClosedLidGuardResponse.self, from: data)
            guard response.id == request.id else { throw ClosedLidStandardGuardError.invalidResponse }
            return response
        } catch {
            invalidateProcess()
            _ = selectorDriver.setEnabled(false)
            throw error
        }
    }

    private func ensureProcess() throws {
        if let process, process.isRunning {
            return
        }
        invalidateProcess(terminate: false)
        guard restartCount < 3 else { throw ClosedLidStandardGuardError.unavailable }
        restartCount += 1
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = try executableURL()
        process.arguments = ["--parent-pid", String(Darwin.getpid())]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        process.environment = TerminalEnvironmentPolicy.sanitizedEnvironment(from: ProcessInfo.processInfo.environment)
        expectedExit = false
        process.terminationHandler = { [weak self, weak process] _ in
            guard let self, let process else { return }
            self.queue.async {
                guard self.process === process else { return }
                let wasExpected = self.expectedExit
                self.input = nil
                self.output = nil
                self.reader = nil
                self.process = nil
                _ = self.selectorDriver.setEnabled(false)
                if !wasExpected {
                    self.onUnexpectedExit?()
                }
            }
        }
        self.process = process
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading
        reader = ClosedLidJSONLineReader(descriptor: outputPipe.fileHandleForReading.fileDescriptor)
        do {
            try process.run()
        } catch {
            invalidateProcess(terminate: false)
            throw error
        }
    }

    private func invalidateProcess(terminate: Bool = true) {
        expectedExit = true
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

    private func perform<T: Sendable>(_ operation: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: operation()) }
        }
    }

    private func performThrowing<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    do { try continuation.resume(returning: operation()) } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: {
            self.queue.async {
                self.process?.terminate()
                try? self.output?.close()
                _ = self.selectorDriver.setEnabled(false)
            }
        }
    }
}

enum ClosedLidGuardExecutableLocator {
    static func url() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["KAJI_CLOSED_LID_GUARD_EXECUTABLE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty
        {
            return try validated(URL(fileURLWithPath: override))
        }
        var candidates: [URL] = []
        if let executable = Bundle.main.executableURL {
            candidates.append(executable.deletingLastPathComponent().appendingPathComponent("KajiClosedLidGuard"))
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        candidates.append(root.appendingPathComponent(".build/debug/KajiClosedLidGuard"))
        candidates.append(root.appendingPathComponent(".build/arm64-apple-macosx/debug/KajiClosedLidGuard"))
        candidates.append(root.appendingPathComponent(".build/x86_64-apple-macosx/debug/KajiClosedLidGuard"))
        guard let candidate = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw ClosedLidStandardGuardError.unavailable
        }
        return candidate
    }

    private static func validated(_ url: URL) throws -> URL {
        guard url.isFileURL, FileManager.default.isExecutableFile(atPath: url.path) else {
            throw ClosedLidStandardGuardError.unavailable
        }
        return url
    }
}
