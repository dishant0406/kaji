import Darwin
import Foundation
import KajiPowerHelperProtocol

protocol PMSetRunning: Sendable {
    func run(_ command: PMSetCommand) -> PMSetResult
}

struct PMSetResult: Equatable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
    let timedOut: Bool

    var succeeded: Bool {
        exitCode == 0 && !timedOut
    }
}

private final class BoundedDataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var storage = Data()

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ data: Data) {
        lock.withLock {
            let remaining = limit - storage.count
            if remaining > 0 {
                storage.append(data.prefix(remaining))
            }
        }
    }

    var data: Data {
        lock.withLock { storage }
    }
}

struct PMSetRunner: PMSetRunning {
    let timeout: TimeInterval
    let maximumOutputBytes: Int

    init(timeout: TimeInterval = 5, maximumOutputBytes: Int = 65536) {
        self.timeout = min(max(timeout, 1), 10)
        self.maximumOutputBytes = min(max(maximumOutputBytes, 1024), 262_144)
    }

    func run(_ command: PMSetCommand) -> PMSetResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputCollector = BoundedDataCollector(limit: maximumOutputBytes)
        let errorCollector = BoundedDataCollector(limit: maximumOutputBytes)
        outputPipe.fileHandleForReading.readabilityHandler = { handle in outputCollector.append(handle.availableData) }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in errorCollector.append(handle.availableData) }
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return PMSetResult(exitCode: -1, standardOutput: "", standardError: error.localizedDescription, timedOut: false)
        }

        let timedOut = semaphore.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            if semaphore.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = semaphore.wait(timeout: .now() + 1)
            }
        }
        outputCollector.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        errorCollector.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil

        return PMSetResult(
            exitCode: process.isRunning ? -1 : process.terminationStatus,
            standardOutput: String(decoding: outputCollector.data, as: UTF8.self),
            standardError: String(decoding: errorCollector.data, as: UTF8.self),
            timedOut: timedOut
        )
    }
}

final class PowerHelperService: NSObject, KajiPowerHelperXPCProtocol, @unchecked Sendable {
    private let runner: any PMSetRunning
    private let queue = DispatchQueue(label: "com.kaji.power-helper.service")
    private let watchdogTimeout: TimeInterval
    private var watchdog: PowerHelperWatchdog
    private var keepAwake = false

    init(runner: any PMSetRunning = PMSetRunner(), watchdogTimeout: TimeInterval = 15) {
        self.runner = runner
        self.watchdogTimeout = min(max(watchdogTimeout, 10), 30)
        watchdog = PowerHelperWatchdog(timeout: self.watchdogTimeout)
        super.init()
    }

    func restoreAtStartup() -> Bool {
        queue.sync { mutateAndVerify(disabled: false).0 }
    }

    func watchdogTick(now: Date = Date()) {
        queue.sync {
            guard keepAwake, watchdog.shouldRestore(at: now) else { return }
            _ = mutateAndVerify(disabled: false)
        }
    }

    func setKeepAwake(_ enabled: Bool, withReply reply: @escaping (Bool, String?) -> Void) {
        let result = queue.sync { mutateAndVerify(disabled: enabled) }
        reply(result.0, result.1)
    }

    func getState(withReply reply: @escaping (Bool, Bool, String?) -> Void) {
        let result = queue.sync { readState() }
        reply(result.0 != nil, result.0 ?? false, result.1)
    }

    func heartbeat(withReply reply: @escaping (Bool) -> Void) {
        let alive = queue.sync {
            guard keepAwake else { return false }
            let result = readState()
            guard result.0 == true else { return false }
            watchdog.heartbeat()
            return true
        }
        reply(alive)
    }

    func version(withReply reply: @escaping (Int) -> Void) {
        reply(kajiPowerHelperVersion)
    }

    func restoreNow(withReply reply: @escaping (Bool, String?) -> Void) {
        setKeepAwake(false, withReply: reply)
    }

    private func mutateAndVerify(disabled: Bool) -> (Bool, String?) {
        let mutation = runner.run(.setSleepDisabled(disabled))
        guard mutation.succeeded else {
            return mutationFailure(disabled: disabled, message: commandError(mutation))
        }
        let state = readState()
        guard state.0 == disabled else {
            return mutationFailure(
                disabled: disabled,
                message: state.1 ?? "pmset did not report the requested SleepDisabled state"
            )
        }
        keepAwake = disabled
        watchdog = PowerHelperWatchdog(timeout: watchdogTimeout)
        return (true, nil)
    }

    private func mutationFailure(disabled: Bool, message: String) -> (Bool, String?) {
        guard disabled else {
            keepAwake = true
            return (false, message)
        }
        let restore = runner.run(.setSleepDisabled(false))
        let restoredState = restore.succeeded ? readState() : (nil, commandError(restore))
        guard restore.succeeded, restoredState.0 == false else {
            keepAwake = true
            let restoreMessage = restoredState.1 ?? "normal sleep state could not be verified"
            return (false, "\(message). Restore failed: \(restoreMessage)")
        }
        keepAwake = false
        return (false, message)
    }

    private func readState() -> (Bool?, String?) {
        let result = runner.run(.readState)
        guard result.succeeded else { return (nil, commandError(result)) }
        guard let state = PMSetStateParser.sleepDisabled(from: result.standardOutput) else {
            return (nil, "pmset output did not contain a valid SleepDisabled value")
        }
        return (state, nil)
    }

    private func commandError(_ result: PMSetResult) -> String {
        if result.timedOut { return "pmset timed out" }
        let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "pmset failed with status \(result.exitCode)" : String(message.prefix(512))
    }
}
