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
    func foregroundGroupOnlySelectsDisplayIdentityWithoutExcludingBackgroundWorkers() {
        let shell = ProcessResourceSample(
            pid: 10,
            parentPID: 1,
            processGroupID: 10,
            processName: "zsh",
            cpuTimeNanos: 100,
            residentBytes: 10,
            footprintBytes: 10,
            threadCount: 1
        )
        let foreground = ProcessResourceSample(
            pid: 11,
            parentPID: 10,
            processGroupID: 11,
            processName: "vim",
            cpuTimeNanos: 400,
            residentBytes: 40,
            footprintBytes: 40,
            threadCount: 2
        )
        let worker = ProcessResourceSample(
            pid: 12,
            parentPID: 10,
            processGroupID: 12,
            processName: "agent",
            cpuTimeNanos: 900,
            residentBytes: 90,
            footprintBytes: 90,
            threadCount: 3
        )

        let sample = ProcessResourceSampler.aggregateProcessTree(
            rootPID: 10,
            samples: [shell, foreground, worker],
            parentPIDByPID: [10: 1, 11: 10, 12: 10],
            foregroundProcessGroupID: 11
        )

        #expect(sample?.representativePID == 11)
        #expect(sample?.processName == "vim")
        #expect(Set(sample?.processes.map(\.pid) ?? []) == [10, 11, 12])
        #expect(sample?.memoryBytes == 140)
        #expect(sample?.threadCount == 6)
    }

    @Test
    func snapshotTreeUsesOneImmutableProcessTable() {
        let root = ProcessResourceSample(
            pid: 20,
            parentPID: 1,
            processGroupID: 20,
            startIdentity: .init(seconds: 100, microseconds: 2),
            processName: "shell",
            cpuTimeNanos: 10,
            residentBytes: 20,
            footprintBytes: 30,
            threadCount: 1
        )
        let child = ProcessResourceSample(
            pid: 21,
            parentPID: 20,
            processGroupID: 21,
            startIdentity: .init(seconds: 101, microseconds: 3),
            processName: "worker",
            cpuTimeNanos: 20,
            residentBytes: 40,
            footprintBytes: 50,
            threadCount: 2
        )
        let snapshot = DarwinProcessTableSnapshot(processesByPID: [20: root, 21: child])

        let sample = ProcessResourceSampler.sampleProcessTree(rootPID: 20, snapshot: snapshot)

        #expect(sample?.processes == [root, child])
        #expect(sample?.memoryBytes == 80)
    }

    @Test
    func ttyPathValidationRejectsTraversalAndNonTTYDevices() {
        #expect(ProcessResourceSampler.validatedTTYPath("ttys012") == "/dev/ttys012")
        #expect(ProcessResourceSampler.validatedTTYPath("/dev/ttys012") == "/dev/ttys012")
        #expect(ProcessResourceSampler.validatedTTYPath("../../etc/passwd") == nil)
        #expect(ProcessResourceSampler.validatedTTYPath("null") == nil)
        #expect(ProcessResourceSampler.validatedTTYPath("tty/../disk0") == nil)
    }

    @Test
    func liveChildMemoryIsIncludedUntilChildExits() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else { return }
        let process = Process()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "/usr/bin/python3 -c 'import time; value=bytearray(32*1024*1024); time.sleep(5)' & wait; read line",
        ]
        process.standardInput = input
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        defer {
            input.fileHandleForWriting.write(Data("done\n".utf8))
            process.terminate()
        }

        let rootPID = Int32(process.processIdentifier)
        var liveTree: ProcessTreeResourceSample?
        for _ in 0 ..< 100 {
            if let snapshot = try? ProcessResourceSampler.snapshot(),
               let tree = ProcessResourceSampler.sampleProcessTree(rootPID: rootPID, snapshot: snapshot),
               tree.processes.count > 1
            {
                liveTree = tree
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let live = try #require(liveTree)
        let liveRoot = try #require(live.processes.first { $0.pid == rootPID })
        #expect(live.memoryBytes > liveRoot.memoryBytes)

        var shellOnlyTree: ProcessTreeResourceSample?
        for _ in 0 ..< 140 {
            if let snapshot = try? ProcessResourceSampler.snapshot(),
               let tree = ProcessResourceSampler.sampleProcessTree(rootPID: rootPID, snapshot: snapshot),
               tree.processes.count == 1
            {
                shellOnlyTree = tree
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let shellOnly = try #require(shellOnlyTree)
        #expect(shellOnly.memoryBytes == shellOnly.processes[0].memoryBytes)
    }

    @Test
    func machTimeConverterProducesNonZeroNanoseconds() {
        #expect(MachTimeConverter.toNanoseconds(1) > 0)
    }
}
