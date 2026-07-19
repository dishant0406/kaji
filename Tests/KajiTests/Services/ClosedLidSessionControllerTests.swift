import ClosedLidCore
import Darwin
import Foundation
import IOKit
import KajiPowerHelperProtocol
import Testing

@testable import Kaji

@MainActor
struct ClosedLidSessionControllerTests {
    @Test
    func successfulProbeWithoutAttestationNeedsPhysicalVerification() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = RecordingClosedLidStandardSession()
        let controller = makeController(defaults: defaults, session: session)

        await controller.probeCapability()

        #expect(controller.status == .off)
        #expect(controller.standardCompatibility == .needsVerification)
        #expect(session.selectorValues == [true, false])
    }

    @Test
    func attestationIsScopedToExactHardwareAndOSIdentity() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = RecordingClosedLidStandardSession()
        let identity = ClosedLidHardwareIdentity(model: "Mac14,9", osMajor: 26, osMinor: 5, osBuild: "25F90")
        let controller = ClosedLidSessionController(
            defaults: defaults,
            standardSession: session,
            hardwareIdentity: { identity }
        )
        await controller.probeCapability()
        controller.recordStandardPhysicalTest(success: true)
        #expect(controller.standardCompatibility == .verified)

        let changedBuild = ClosedLidSessionController(
            defaults: defaults,
            standardSession: RecordingClosedLidStandardSession(),
            hardwareIdentity: {
                ClosedLidHardwareIdentity(model: "Mac14,9", osMajor: 26, osMinor: 5, osBuild: "25F91")
            }
        )
        await changedBuild.probeCapability()

        #expect(changedBuild.standardCompatibility == .needsVerification)
    }

    @Test
    func startDoesNotReportActiveUntilGuardConfirmsArm() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = RecordingClosedLidStandardSession()
        session.armError = ClosedLidStandardGuardError.selectorFailure(kIOReturnNotPermitted)
        let controller = makeController(defaults: defaults, session: session)
        await controller.probeCapability()

        await controller.start(mode: .standard)

        #expect(controller.status == .failed("Closed-lid selector failed (\(kIOReturnNotPermitted))"))
        #expect(session.directRestoreCount == 1)
    }

    @Test
    func guardDeathImmediatelyRestoresAndSafetyStops() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = RecordingClosedLidStandardSession()
        let controller = makeController(defaults: defaults, session: session)
        await controller.probeCapability()
        await controller.start(mode: .standard)
        #expect(controller.status == .activeStandard)

        session.onUnexpectedExit?()
        await Task.yield()

        #expect(session.directRestoreCount == 1)
        #expect(controller.status == .safetyStopped(.heartbeatLost))
    }

    @Test
    func explicitSafetyStopRestoresThenPreservesReason() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = RecordingClosedLidStandardSession()
        let controller = makeController(defaults: defaults, session: session)
        await controller.probeCapability()
        await controller.start(mode: .standard)

        await controller.safetyStop(reason: .batteryBelowFloor)

        #expect(session.disarmCount == 1)
        #expect(controller.status == .safetyStopped(.batteryBelowFloor))
    }

    @Test
    func powerProtectStartsOnlyAfterVerifiedLiveStateAndRestores() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let powerProtect = RecordingPowerProtectManager()
        let controller = ClosedLidSessionController(
            defaults: defaults,
            standardSession: RecordingClosedLidStandardSession(),
            powerProtect: powerProtect,
            hardwareIdentity: {
                ClosedLidHardwareIdentity(model: "Mac14,9", osMajor: 26, osMinor: 5, osBuild: "25F90")
            }
        )

        await controller.start(mode: .powerProtect)
        #expect(controller.status == .activePowerProtect)
        #expect(powerProtect.enableCount == 1)

        await controller.stop()
        #expect(controller.status == .off)
        #expect(powerProtect.restoreCount == 1)
    }

    @Test
    func unverifiedPowerProtectNeverReportsActive() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let powerProtect = RecordingPowerProtectManager()
        powerProtect.verifyEnable = false
        let controller = ClosedLidSessionController(
            defaults: defaults,
            standardSession: RecordingClosedLidStandardSession(),
            powerProtect: powerProtect
        )

        await controller.start(mode: .powerProtect)

        if case .failed = controller.status {} else {
            Issue.record("Expected failed Power Protect status")
        }
        #expect(powerProtect.restoreCount == 1)
    }
    @Test
    func safetyReasonRemainsVisibleWhenRestoreFails() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let powerProtect = RecordingPowerProtectManager()
        let controller = ClosedLidSessionController(
            defaults: defaults,
            standardSession: RecordingClosedLidStandardSession(),
            powerProtect: powerProtect
        )
        await controller.start(mode: .powerProtect)
        powerProtect.restoreError = PowerHelperError.verificationFailed

        await controller.safetyStop(reason: .batteryBelowFloor)

        if case let .failed(message) = controller.status {
            #expect(message.contains("Battery safety floor reached"))
        } else {
            Issue.record("Expected failed safety restoration status")
        }
    }

    @Test
    func terminationDrainFailsWhenPowerProtectCannotRestore() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let powerProtect = RecordingPowerProtectManager()
        let controller = ClosedLidSessionController(
            defaults: defaults,
            standardSession: RecordingClosedLidStandardSession(),
            powerProtect: powerProtect
        )
        await controller.start(mode: .powerProtect)
        powerProtect.restoreError = PowerHelperError.verificationFailed

        let canTerminate = await controller.shutdownForTermination()

        #expect(!canTerminate)
        #expect(controller.requiresTerminationDrain)
        if case .failed = controller.status {} else {
            Issue.record("Expected failed restoration status")
        }
    }


    @Test
    func settingsAreClampedAndPersisted() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = makeController(defaults: defaults, session: RecordingClosedLidStandardSession())

        controller.updateSettings(ClosedLidSafetySettings(durationMinutes: 0, batteryFloorPercent: 500))

        let restored = makeController(defaults: defaults, session: RecordingClosedLidStandardSession())
        #expect(restored.settings.durationMinutes == 1)
        #expect(restored.settings.batteryFloorPercent == 50)
    }

    private func makeController(
        defaults: UserDefaults,
        session: RecordingClosedLidStandardSession
    ) -> ClosedLidSessionController {
        ClosedLidSessionController(
            defaults: defaults,
            standardSession: session,
            hardwareIdentity: {
                ClosedLidHardwareIdentity(model: "Mac14,9", osMajor: 26, osMinor: 5, osBuild: "25F90")
            }
        )
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let name = "ClosedLidSessionControllerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { fatalError("Unable to create defaults") }
        return (defaults, name)
    }
}

final class RecordingClosedLidStandardSession: ClosedLidStandardSessionManaging, @unchecked Sendable {
    var onUnexpectedExit: (@Sendable () -> Void)?
    var selectorValues: [Bool] = []
    var armError: Error?
    var disarmError: Error?
    var directRestoreCount = 0
    var disarmCount = 0
    private let evidence = ClosedLidStandardSessionEvidence(
        sessionID: UUID(),
        armedMonotonicNanoseconds: 1,
        lastHeartbeatMonotonicNanoseconds: 1,
        heartbeatCount: 0
    )

    func probeCapability() async -> ClosedLidSelectorProbeResult {
        selectorValues.append(contentsOf: [true, false])
        return ClosedLidSelectorProbeResult(enableResult: KERN_SUCCESS, restoreResult: KERN_SUCCESS)
    }

    func arm() async throws -> ClosedLidStandardSessionEvidence {
        if let armError { throw armError }
        return evidence
    }

    func disarm() async throws {
        disarmCount += 1
        if let disarmError { throw disarmError }
    }

    func status() async throws -> ClosedLidGuardResponse {
        ClosedLidGuardResponse(id: UUID(), state: .armed, selectorResult: KERN_SUCCESS, evidence: evidence)
    }

    func heartbeat() async throws -> ClosedLidStandardSessionEvidence { evidence }
    func shutdown() async {}

    func directRestore() -> kern_return_t {
        directRestoreCount += 1
        return KERN_SUCCESS
    }
}

@MainActor
private final class RecordingPowerProtectManager: PowerProtectManaging {
    var state: PowerHelperRegistrationState = .ready(sleepDisabled: false)
    var restoreError: Error?
    var verifyEnable = true
    var enableCount = 0
    var restoreCount = 0

    func probeCapability() async {}

    func enableVerified() async throws {
        enableCount += 1
        state = .ready(sleepDisabled: verifyEnable)
    }

    func restore() async throws {
        restoreCount += 1
        if let restoreError { throw restoreError }
        state = .ready(sleepDisabled: false)
    }

    func heartbeat() async -> Bool {
        state == .ready(sleepDisabled: true)
    }

    func refresh() async {}
}
