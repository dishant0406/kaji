import Foundation
import Testing

@testable import Kaji

struct ProcessResourceSamplerTests {
    @Test
    func aggregateUsesProcessGroupLeaderWhenAvailable() {
        let leader = ProcessResourceSample(
            pid: 410,
            processName: "python",
            cpuTimeNanos: 2_000_000_000,
            residentBytes: 80 * 1_024 * 1_024,
            footprintBytes: 180 * 1_024 * 1_024,
            threadCount: 3
        )
        let child = ProcessResourceSample(
            pid: 411,
            processName: "worker",
            cpuTimeNanos: 1_000_000_000,
            residentBytes: 60 * 1_024 * 1_024,
            footprintBytes: 120 * 1_024 * 1_024,
            threadCount: 2
        )

        let sample = ProcessResourceSampler.aggregate(processGroupID: 410, samples: [leader, child])

        #expect(sample?.processGroupID == 410)
        #expect(sample?.representativePID == 410)
        #expect(sample?.processName == "python")
        #expect(sample?.cpuTimeNanos == 3_000_000_000)
        #expect(sample?.memoryBytes == UInt64(300 * 1_024 * 1_024))
        #expect(sample?.threadCount == 5)
    }

    @Test
    func aggregateFallsBackToBusiestMemberWhenLeaderMissing() {
        let shell = ProcessResourceSample(
            pid: 500,
            processName: "zsh",
            cpuTimeNanos: 500_000_000,
            residentBytes: 20 * 1_024 * 1_024,
            footprintBytes: 24 * 1_024 * 1_024,
            threadCount: 1
        )
        let command = ProcessResourceSample(
            pid: 501,
            processName: "swift",
            cpuTimeNanos: 4_000_000_000,
            residentBytes: 150 * 1_024 * 1_024,
            footprintBytes: 240 * 1_024 * 1_024,
            threadCount: 6
        )

        let sample = ProcessResourceSampler.aggregate(processGroupID: 999, samples: [shell, command])

        #expect(sample?.representativePID == 501)
        #expect(sample?.processName == "swift")
    }

    @Test
    func descendantProcessIDsIncludeNestedChildren() {
        let pids = ProcessResourceSampler.descendantProcessIDs(
            rootPID: 10,
            parentPIDByPID: [
                11: 10,
                12: 11,
                13: 10,
                20: 1,
            ]
        )

        #expect(Set(pids) == [10, 11, 12, 13])
    }

    @Test
    func aggregateProcessTreeUsesBusiestDescendantAsRepresentative() {
        let shell = ProcessResourceSample(
            pid: 10,
            processName: "zsh",
            cpuTimeNanos: 100_000_000,
            residentBytes: 20 * 1_024 * 1_024,
            footprintBytes: 24 * 1_024 * 1_024,
            threadCount: 1
        )
        let command = ProcessResourceSample(
            pid: 11,
            processName: "swift",
            cpuTimeNanos: 3_000_000_000,
            residentBytes: 90 * 1_024 * 1_024,
            footprintBytes: 160 * 1_024 * 1_024,
            threadCount: 5
        )
        let unrelated = ProcessResourceSample(
            pid: 20,
            processName: "node",
            cpuTimeNanos: 8_000_000_000,
            residentBytes: 250 * 1_024 * 1_024,
            footprintBytes: 300 * 1_024 * 1_024,
            threadCount: 8
        )

        let sample = ProcessResourceSampler.aggregateProcessTree(
            rootPID: 10,
            samples: [shell, command, unrelated],
            parentPIDByPID: [11: 10, 20: 1]
        )

        #expect(sample?.rootPID == 10)
        #expect(sample?.representativePID == 11)
        #expect(sample?.processName == "swift")
        #expect(sample?.cpuTimeNanos == 3_100_000_000)
        #expect(sample?.memoryBytes == UInt64(184 * 1_024 * 1_024))
        #expect(sample?.threadCount == 6)
    }

    @Test
    func cpuPercentResolverUsesElapsedDelta() {
        let value = ResourceMonitorCPUPercentResolver.resolve(
            currentCPUTimeNanos: 3_500_000_000,
            baselineCPUTimeNanos: 2_000_000_000,
            elapsed: 3
        )

        #expect(value == 50)
    }

    @Test
    func machTimeConverterProducesNonZeroNanoseconds() {
        #expect(MachTimeConverter.toNanoseconds(1) > 0)
    }
}
