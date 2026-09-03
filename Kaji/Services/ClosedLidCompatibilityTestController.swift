import ClosedLidCore
import Foundation
import Observation

enum ClosedLidCompatibilityTestState: Equatable {
    case idle
    case probing
    case ready
    case arming
    case awaitingClose
    case evaluating
    case passed
    case failed(String)
    case cancelling
}

struct ClosedLidCompatibilityTestEvidence: Equatable {
    let samples: [ClosedLidStandardSessionEvidence]
    let pmsetBaseline: String
    let pmsetAfterTest: String
}

struct ClosedLidCompatibilityTestEvaluation: Equatable {
    let succeeded: Bool
    let detail: String
}

enum ClosedLidCompatibilityTestPolicy {
    static let minimumTestDurationNanoseconds: UInt64 = 15_000_000_000
    static let maximumHeartbeatGapNanoseconds: UInt64 = 12_000_000_000

    static func evaluate(_ evidence: ClosedLidCompatibilityTestEvidence) -> ClosedLidCompatibilityTestEvaluation {
        let samples = evidence.samples
            .reduce(into: [UInt64: ClosedLidStandardSessionEvidence]()) { result, sample in
                result[sample.heartbeatCount] = sample
            }
            .values
            .sorted { $0.lastHeartbeatMonotonicNanoseconds < $1.lastHeartbeatMonotonicNanoseconds }
        guard let first = samples.first, let last = samples.last,
              samples.allSatisfy({ $0.sessionID == first.sessionID }),
              last.heartbeatCount >= first.heartbeatCount + 2,
              last.lastHeartbeatMonotonicNanoseconds >= first.armedMonotonicNanoseconds
        else {
            return .init(succeeded: false, detail: "The external continuity guard did not provide enough heartbeat evidence.")
        }
        let duration = last.lastHeartbeatMonotonicNanoseconds - first.armedMonotonicNanoseconds
        guard duration >= minimumTestDurationNanoseconds else {
            return .init(succeeded: false, detail: "Keep the lid closed for at least 15 seconds, then try again.")
        }
        for pair in zip(samples, samples.dropFirst()) {
            let earlier = pair.0.lastHeartbeatMonotonicNanoseconds
            let later = pair.1.lastHeartbeatMonotonicNanoseconds
            guard later >= earlier, later - earlier <= maximumHeartbeatGapNanoseconds else {
                return .init(
                    succeeded: false,
                    detail: "The continuity guard paused while the lid was closed, so Standard mode was not verified."
                )
            }
        }
        guard evidence.pmsetAfterTest.hasPrefix(evidence.pmsetBaseline) else {
            return .init(succeeded: false, detail: "The macOS sleep log changed unexpectedly and could not prove continuity.")
        }
        let newLog = evidence.pmsetAfterTest.dropFirst(evidence.pmsetBaseline.count).lowercased()
        let sleepMarkers = ["entering sleep", "sleep entered", "clamshell sleep"]
        guard !sleepMarkers.contains(where: newLog.contains) else {
            return .init(succeeded: false, detail: "macOS recorded sleep during the test, so Standard mode was not verified.")
        }
        return .init(
            succeeded: true,
            detail: "External heartbeats continued and macOS recorded no sleep. Standard mode is verified for this Mac and OS build."
        )
    }
}

enum ClosedLidPMSetLogReader {
    static func snapshot() async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["-g", "log"]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let value = String(data: data, encoding: .utf8),
                  value.utf8.count <= 8_000_000
            else { throw ClosedLidPowerSnapshotError.powerSourcesUnavailable }
            return value
        }.value
    }
}

@MainActor @Observable
final class ClosedLidCompatibilityTestController {
    static let shared = ClosedLidCompatibilityTestController()

    private let sessionController: ClosedLidSessionController
    private let logSnapshot: @Sendable () async throws -> String
    private var samplingTask: Task<Void, Never>?
    private var samples: [ClosedLidStandardSessionEvidence] = []
    private var pmsetBaseline = ""

    private(set) var state: ClosedLidCompatibilityTestState = .idle
    private(set) var detail = "Run the software probe before the physical lid-close test."

    init(
        sessionController: ClosedLidSessionController = .shared,
        logSnapshot: @escaping @Sendable () async throws -> String = ClosedLidPMSetLogReader.snapshot
    ) {
        self.sessionController = sessionController
        self.logSnapshot = logSnapshot
    }

    var canEvaluate: Bool {
        guard state == .awaitingClose else { return false }
        let uniqueHeartbeats = Set(samples.map(\.heartbeatCount))
        guard uniqueHeartbeats.count >= 3, let first = samples.first, let last = samples.last else { return false }
        return last.lastHeartbeatMonotonicNanoseconds >= first.armedMonotonicNanoseconds + ClosedLidCompatibilityTestPolicy
            .minimumTestDurationNanoseconds
    }

    func probe() async {
        guard state != .arming, state != .awaitingClose, state != .evaluating, state != .cancelling else { return }
        state = .probing
        detail = "Checking selector 12 and the fail-safe guard…"
        await sessionController.probeCapability()
        if sessionController.selectorCapability?.isAvailable == true {
            state = .ready
            detail = "Software checks passed. Start the test, close the lid for 15 seconds, then reopen it."
        } else {
            state = .failed("Selector 12 is unavailable on this Mac and OS build.")
            detail = "Standard mode cannot be tested here. Normal sleep remains enabled."
        }
    }

    func arm() async {
        guard state == .ready else { return }
        state = .arming
        detail = "Arming the external fail-safe guard…"
        do {
            pmsetBaseline = try await logSnapshot()
            samples.removeAll(keepingCapacity: true)
            await sessionController.start(mode: .standard)
            guard sessionController.status == .activeStandard,
                  let initial = await sessionController.standardSessionEvidence()
            else {
                await restoreAfterFailure("Standard mode could not be armed. Normal sleep was restored.")
                return
            }
            samples.append(initial)
            state = .awaitingClose
            detail = "Close the lid now. Keep the Mac ventilated and unloaded. Reopen after at least 15 seconds."
            startSampling()
        } catch {
            await restoreAfterFailure("The macOS sleep log could not be read. Normal sleep was restored.")
        }
    }

    func evaluate() async {
        guard state == .awaitingClose else { return }
        state = .evaluating
        detail = "Restoring normal sleep before evaluating evidence…"
        samplingTask?.cancel()
        samplingTask = nil
        if let final = await sessionController.standardSessionEvidence() {
            append(final)
        }
        await sessionController.stop()
        guard sessionController.status == .off else {
            state = .failed("Normal sleep could not be confirmed after the test.")
            detail = "Do not close the lid again until normal sleep has been restored."
            return
        }
        do {
            let currentLog = try await logSnapshot()
            let evaluation = ClosedLidCompatibilityTestPolicy.evaluate(.init(
                samples: samples,
                pmsetBaseline: pmsetBaseline,
                pmsetAfterTest: currentLog
            ))
            sessionController.recordStandardPhysicalTest(success: evaluation.succeeded)
            state = evaluation.succeeded ? .passed : .failed("The physical test did not verify Standard mode.")
            detail = evaluation.detail
        } catch {
            sessionController.recordStandardPhysicalTest(success: false)
            state = .failed("The macOS sleep log could not be evaluated.")
            detail = "Normal sleep was restored, but no compatibility attestation was recorded."
        }
    }

    func cancel() async {
        guard state == .arming || state == .awaitingClose || state == .evaluating else {
            state = .idle
            detail = "Run the software probe before the physical lid-close test."
            return
        }
        state = .cancelling
        detail = "Forcing normal sleep restoration…"
        samplingTask?.cancel()
        samplingTask = nil
        await sessionController.stop()
        if sessionController.status == .off {
            state = .idle
            detail = "Test cancelled. Normal sleep is restored."
        } else {
            state = .failed("Normal sleep could not be confirmed after cancellation.")
            detail = "Do not close the lid again until normal sleep has been restored."
        }
    }

    private func startSampling() {
        samplingTask?.cancel()
        samplingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled, self.state == .awaitingClose else { return }
                if let evidence = await self.sessionController.standardSessionEvidence() {
                    self.append(evidence)
                } else {
                    await self.restoreAfterFailure("The external continuity guard stopped responding. Normal sleep was restored.")
                    return
                }
            }
        }
    }

    private func append(_ evidence: ClosedLidStandardSessionEvidence) {
        if let last = samples.last, last.heartbeatCount == evidence.heartbeatCount {
            return
        }
        samples.append(evidence)
    }

    private func restoreAfterFailure(_ message: String) async {
        samplingTask?.cancel()
        samplingTask = nil
        await sessionController.stop()
        sessionController.recordStandardPhysicalTest(success: false)
        state = .failed(message)
        detail = message
    }
}
