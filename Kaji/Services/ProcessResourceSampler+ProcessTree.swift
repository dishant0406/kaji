import Foundation

struct ProcessTreeResourceSample: Equatable {
    let rootPID: Int32
    let representativePID: Int32
    let representativeProcessGroupID: Int32?
    let processName: String
    let processes: [ProcessResourceSample]
    let cpuTimeNanos: UInt64
    let memoryBytes: UInt64
    let threadCount: Int
}

extension ProcessResourceSampler {
    static func sampleProcessTree(rootPID: Int32) -> ProcessTreeResourceSample? {
        guard let snapshot = try? snapshot() else { return nil }
        return sampleProcessTree(rootPID: rootPID, snapshot: snapshot)
    }

    static func sampleProcessTree(
        rootPID: Int32,
        snapshot: DarwinProcessTableSnapshot,
        foregroundProcessGroupID: Int32? = nil
    ) -> ProcessTreeResourceSample? {
        aggregateProcessTree(
            rootPID: rootPID,
            samples: snapshot.processes,
            parentPIDByPID: snapshot.processesByPID.mapValues(\.parentPID),
            foregroundProcessGroupID: foregroundProcessGroupID
        )
    }

    static func aggregateProcessTree(
        rootPID: Int32,
        samples: [ProcessResourceSample],
        parentPIDByPID: [Int32: Int32],
        foregroundProcessGroupID: Int32? = nil
    ) -> ProcessTreeResourceSample? {
        guard !samples.isEmpty else { return nil }
        let descendantIDs = Set(descendantProcessIDs(rootPID: rootPID, parentPIDByPID: parentPIDByPID))
        let treeSamples = samples.filter { descendantIDs.contains($0.pid) }.sorted { $0.pid < $1.pid }
        guard !treeSamples.isEmpty else { return nil }

        let foregroundSamples = foregroundProcessGroupID.map { groupID in
            treeSamples.filter { $0.processGroupID == groupID }
        } ?? []
        let representativeCandidates = foregroundSamples.isEmpty ? treeSamples : foregroundSamples
        let representative = representativeCandidates.max { lhs, rhs in
            if lhs.pid == rootPID { return true }
            if rhs.pid == rootPID { return false }
            if lhs.cpuTimeNanos == rhs.cpuTimeNanos {
                return lhs.memoryBytes < rhs.memoryBytes
            }
            return lhs.cpuTimeNanos < rhs.cpuTimeNanos
        }
        guard let representative else { return nil }

        return ProcessTreeResourceSample(
            rootPID: rootPID,
            representativePID: representative.pid,
            representativeProcessGroupID: foregroundProcessGroupID ?? representative.processGroupID,
            processName: representative.processName,
            processes: treeSamples,
            cpuTimeNanos: treeSamples.reduce(0) { $0 + $1.cpuTimeNanos },
            memoryBytes: treeSamples.reduce(0) { $0 + $1.memoryBytes },
            threadCount: treeSamples.reduce(0) { $0 + $1.threadCount }
        )
    }

    static func descendantProcessIDs(rootPID: Int32, parentPIDByPID: [Int32: Int32]) -> [Int32] {
        guard rootPID > 0 else { return [] }
        var childrenByParent: [Int32: [Int32]] = [:]
        childrenByParent.reserveCapacity(parentPIDByPID.count)
        for (pid, parentPID) in parentPIDByPID {
            childrenByParent[parentPID, default: []].append(pid)
        }

        var result: [Int32] = [rootPID]
        var visited: Set<Int32> = [rootPID]
        var stack: [Int32] = [rootPID]
        while let parent = stack.popLast() {
            for pid in childrenByParent[parent] ?? [] where visited.insert(pid).inserted {
                result.append(pid)
                stack.append(pid)
            }
        }
        return result
    }
}
