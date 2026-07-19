import Foundation
import Testing
@testable import KajiPowerHelper
@testable import KajiPowerHelperProtocol

private final class StubPMSetRunner: PMSetRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [PMSetResult]
    private(set) var commands: [PMSetCommand] = []

    init(_ results: [PMSetResult]) {
        self.results = results
    }

    func run(_ command: PMSetCommand) -> PMSetResult {
        lock.withLock {
            commands.append(command)
            return results.removeFirst()
        }
    }
}

private func pmsetSuccess(_ output: String = "") -> PMSetResult {
    PMSetResult(exitCode: 0, standardOutput: output, standardError: "", timedOut: false)
}

struct PowerHelperServiceTests {
    @Test func startupAlwaysRestoresAndVerifiesNormalSleep() {
        let runner = StubPMSetRunner([pmsetSuccess(), pmsetSuccess("SleepDisabled 0")])
        let service = PowerHelperService(runner: runner)
        #expect(service.restoreAtStartup())
        #expect(runner.commands == [.setSleepDisabled(false), .readState])
    }

    @Test func failedEnableAttemptsFailSafeRestoreAndNeverReportsSuccess() async {
        let runner = StubPMSetRunner([
            PMSetResult(exitCode: 1, standardOutput: "", standardError: "denied", timedOut: false),
            pmsetSuccess(),
            pmsetSuccess("SleepDisabled 0"),
        ])
        let service = PowerHelperService(runner: runner)
        let result = await withCheckedContinuation { continuation in
            service.setKeepAwake(true) { success, message in
                continuation.resume(returning: (success, message))
            }
        }
        #expect(!result.0)
        #expect(result.1 == "denied")
        #expect(runner.commands == [.setSleepDisabled(true), .setSleepDisabled(false), .readState])
    }

    @Test func enableRequiresLiveVerification() async {
        let runner = StubPMSetRunner([
            pmsetSuccess(),
            pmsetSuccess("SleepDisabled 0"),
            pmsetSuccess(),
            pmsetSuccess("SleepDisabled 0"),
        ])
        let service = PowerHelperService(runner: runner)
        let succeeded = await withCheckedContinuation { continuation in
            service.setKeepAwake(true) { success, _ in continuation.resume(returning: success) }
        }
        #expect(!succeeded)
        #expect(runner.commands == [.setSleepDisabled(true), .readState, .setSleepDisabled(false), .readState])
    }

    @Test func failedEnableAndFailedRestoreKeepsWatchdogArmed() async {
        let runner = StubPMSetRunner([
            pmsetSuccess(),
            pmsetSuccess("SleepDisabled 0"),
            PMSetResult(exitCode: 1, standardOutput: "", standardError: "restore denied", timedOut: false),
            PMSetResult(exitCode: 1, standardOutput: "", standardError: "restore denied", timedOut: false),
        ])
        let service = PowerHelperService(runner: runner, watchdogTimeout: 10)
        let enabled = await withCheckedContinuation { continuation in
            service.setKeepAwake(true) { success, _ in continuation.resume(returning: success) }
        }
        #expect(!enabled)

        service.watchdogTick(now: Date().addingTimeInterval(10_000))

        #expect(runner.commands == [
            .setSleepDisabled(true), .readState, .setSleepDisabled(false), .setSleepDisabled(false),
        ])
    }

    @Test func watchdogRestoresAfterHeartbeatLoss() async {
        let origin = Date()
        let runner = StubPMSetRunner([
            pmsetSuccess(),
            pmsetSuccess("SleepDisabled 1"),
            pmsetSuccess(),
            pmsetSuccess("SleepDisabled 0"),
        ])
        let service = PowerHelperService(runner: runner, watchdogTimeout: 10)
        let enabled = await withCheckedContinuation { continuation in
            service.setKeepAwake(true) { success, _ in continuation.resume(returning: success) }
        }
        #expect(enabled)
        service.watchdogTick(now: origin.addingTimeInterval(10_000))
        #expect(runner.commands == [.setSleepDisabled(true), .readState, .setSleepDisabled(false), .readState])
    }
}
