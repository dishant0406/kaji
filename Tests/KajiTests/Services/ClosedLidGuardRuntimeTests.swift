import ClosedLidCore
import Darwin
import Foundation
import IOKit
import Testing

struct ClosedLidGuardRuntimeTests {
    @Test
    func armIsConfirmedOnlyAfterSelectorSucceeds() {
        let driver = RecordingClosedLidSelectorDriver(results: [KERN_SUCCESS, KERN_SUCCESS])
        let session = ClosedLidGuardSession(driver: driver)

        let response = session.handle(ClosedLidGuardRequest(command: .arm))

        #expect(response.state == .armed)
        #expect(response.selectorResult == KERN_SUCCESS)
        #expect(response.evidence != nil)
        #expect(driver.values == [false, true])
    }

    @Test
    func failedArmRestoresAndRemainsDisarmed() {
        let driver = RecordingClosedLidSelectorDriver(results: [KERN_SUCCESS, kIOReturnNotPermitted, KERN_SUCCESS])
        let session = ClosedLidGuardSession(driver: driver)

        let response = session.handle(ClosedLidGuardRequest(command: .arm))

        #expect(response.state == .disarmed)
        #expect(response.selectorResult == kIOReturnNotPermitted)
        #expect(response.evidence == nil)
        #expect(driver.values == [false, true, false])
    }

    @Test
    func heartbeatTimeoutRestoresSelector() {
        let driver = RecordingClosedLidSelectorDriver(results: [KERN_SUCCESS, KERN_SUCCESS, KERN_SUCCESS])
        let clock = TestMonotonicClock(value: 100)
        let session = ClosedLidGuardSession(driver: driver, heartbeatTimeout: 0.000_000_010, now: { clock.value })
        _ = session.handle(ClosedLidGuardRequest(command: .arm))
        clock.value = 1_000_101

        #expect(session.restoreIfHeartbeatExpired())
        #expect(!session.isArmed)
        #expect(driver.values == [false, true, false])
    }

    @Test
    func heartbeatAdvancesExternalEvidence() throws {
        let driver = RecordingClosedLidSelectorDriver(results: [KERN_SUCCESS, KERN_SUCCESS])
        let clock = TestMonotonicClock(value: 100)
        let session = ClosedLidGuardSession(driver: driver, now: { clock.value })
        let armed = session.handle(ClosedLidGuardRequest(command: .arm))
        let sessionID = try #require(armed.evidence?.sessionID)
        clock.value = 150

        let heartbeat = session.handle(ClosedLidGuardRequest(command: .heartbeat))

        #expect(heartbeat.evidence?.sessionID == sessionID)
        #expect(heartbeat.evidence?.lastHeartbeatMonotonicNanoseconds == 150)
        #expect(heartbeat.evidence?.heartbeatCount == 1)
    }

    @Test
    func parentDeathRestoresBeforeRuntimeExits() {
        let input = Pipe()
        let output = Pipe()
        let driver = RecordingClosedLidSelectorDriver(results: [KERN_SUCCESS, KERN_SUCCESS, KERN_SUCCESS])
        let session = ClosedLidGuardSession(driver: driver)
        _ = session.handle(ClosedLidGuardRequest(command: .arm))
        let runtime = ClosedLidGuardRuntime(
            parentPID: 999,
            inputDescriptor: input.fileHandleForReading.fileDescriptor,
            output: output.fileHandleForWriting,
            session: session,
            parentIsAlive: { _ in false }
        )

        #expect(runtime.run() == 0)
        #expect(!session.isArmed)
        #expect(driver.values.suffix(1) == [false])
    }

    @Test
    func stdinEOFRestoresBeforeRuntimeExits() throws {
        let input = Pipe()
        let output = Pipe()
        let driver = RecordingClosedLidSelectorDriver(results: [KERN_SUCCESS, KERN_SUCCESS, KERN_SUCCESS])
        let session = ClosedLidGuardSession(driver: driver)
        _ = session.handle(ClosedLidGuardRequest(command: .arm))
        let runtime = ClosedLidGuardRuntime(
            parentPID: getpid(),
            inputDescriptor: input.fileHandleForReading.fileDescriptor,
            output: output.fileHandleForWriting,
            session: session,
            pollInterval: 0.01
        )
        try input.fileHandleForWriting.close()

        #expect(runtime.run() == 0)
        #expect(!session.isArmed)
        #expect(driver.values.suffix(1) == [false])
    }

    @Test
    func shutdownResponseIsWrittenAndRestores() throws {
        let input = Pipe()
        let output = Pipe()
        let driver = RecordingClosedLidSelectorDriver(results: [KERN_SUCCESS, KERN_SUCCESS])
        let session = ClosedLidGuardSession(driver: driver)
        let request = ClosedLidGuardRequest(command: .shutdown)
        try input.fileHandleForWriting.write(contentsOf: ClosedLidJSONLineCodec.encode(request))
        let runtime = ClosedLidGuardRuntime(
            parentPID: getpid(),
            inputDescriptor: input.fileHandleForReading.fileDescriptor,
            output: output.fileHandleForWriting,
            session: session
        )

        #expect(runtime.run() == 0)
        var reader = ClosedLidJSONLineReader(descriptor: output.fileHandleForReading.fileDescriptor)
        let response = try JSONDecoder().decode(
            ClosedLidGuardResponse.self,
            from: reader.nextFrame(timeout: 1)
        )
        #expect(response.id == request.id)
        #expect(response.state == .disarmed)
        #expect(response.shouldExit)
    }
}

final class TestMonotonicClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: UInt64

    init(value: UInt64) { storedValue = value }

    var value: UInt64 {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}
