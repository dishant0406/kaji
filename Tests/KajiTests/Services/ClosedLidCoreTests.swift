import ClosedLidCore
import Darwin
import Foundation
import IOKit
import Testing

struct ClosedLidCoreTests {
    @Test
    func capabilityProbeEnablesThenAlwaysRestoresAndReturnsExactResults() {
        let driver = RecordingClosedLidSelectorDriver(results: [KERN_SUCCESS, KERN_SUCCESS])

        let result = ClosedLidSelectorCapabilityProbe.run(driver: driver)

        #expect(result == ClosedLidSelectorProbeResult(enableResult: KERN_SUCCESS, restoreResult: KERN_SUCCESS))
        #expect(result.isAvailable)
        #expect(driver.values == [true, false])
    }

    @Test
    func capabilityProbeRestoresAfterEnableFailureAndPreservesBothResults() {
        let driver = RecordingClosedLidSelectorDriver(results: [kIOReturnNotPermitted, kIOReturnNotOpen])

        let result = ClosedLidSelectorCapabilityProbe.run(driver: driver)

        #expect(result.enableResult == kIOReturnNotPermitted)
        #expect(result.restoreResult == kIOReturnNotOpen)
        #expect(!result.isAvailable)
        #expect(driver.values == [true, false])
    }

    @Test
    func liveSelectorProbeEnablesAndImmediatelyRestores() {
        let result = ClosedLidSelectorCapabilityProbe.run(
            driver: IOPMRootDomainClosedLidSelectorDriver()
        )

        #expect(result.enableResult == KERN_SUCCESS)
        #expect(result.restoreResult == KERN_SUCCESS)
        #expect(result.isAvailable)
    }

    @Test
    func splitJSONLineFrameIsReassembledWithoutConsumingNextFrame() throws {
        let pipe = Pipe()
        var reader = ClosedLidJSONLineReader(descriptor: pipe.fileHandleForReading.fileDescriptor)
        let first = ClosedLidGuardRequest(command: .arm)
        let second = ClosedLidGuardRequest(command: .status)
        let firstData = try ClosedLidJSONLineCodec.encode(first)
        let secondData = try ClosedLidJSONLineCodec.encode(second)
        let split = firstData.count / 2

        try pipe.fileHandleForWriting.write(contentsOf: firstData.prefix(split))
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) {
            var remaining = Data(firstData.suffix(from: split))
            remaining.append(secondData)
            try? pipe.fileHandleForWriting.write(contentsOf: remaining)
        }

        let decodedFirst = try JSONDecoder().decode(
            ClosedLidGuardRequest.self,
            from: reader.nextFrame(timeout: 5)
        )
        let decodedSecond = try JSONDecoder().decode(
            ClosedLidGuardRequest.self,
            from: reader.nextFrame(timeout: 5)
        )
        #expect(decodedFirst == first)
        #expect(decodedSecond == second)
    }

    @Test
    func readerTimeoutIsBounded() throws {
        let pipe = Pipe()
        var reader = ClosedLidJSONLineReader(descriptor: pipe.fileHandleForReading.fileDescriptor)
        let start = ContinuousClock.now

        #expect(throws: ClosedLidGuardProtocolError.timedOut) {
            _ = try reader.nextFrame(timeout: 0.02)
        }
        #expect(start.duration(to: .now) < .seconds(1))
    }

    @Test
    func oversizedFrameIsRejected() throws {
        let pipe = Pipe()
        var reader = ClosedLidJSONLineReader(descriptor: pipe.fileHandleForReading.fileDescriptor)
        try pipe.fileHandleForWriting.write(contentsOf: Data(repeating: 0x41, count: closedLidGuardMaximumFrameBytes + 1))

        #expect(throws: ClosedLidGuardProtocolError.frameTooLarge) {
            _ = try reader.nextFrame(timeout: 1)
        }
    }
}

final class RecordingClosedLidSelectorDriver: ClosedLidSelectorDriving, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [kern_return_t]
    private(set) var values: [Bool] = []

    init(results: [kern_return_t]) {
        self.results = results
    }

    func setEnabled(_ enabled: Bool) -> kern_return_t {
        lock.withLock {
            values.append(enabled)
            return results.isEmpty ? KERN_SUCCESS : results.removeFirst()
        }
    }
}
