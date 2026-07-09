import Darwin
import Foundation

struct ProcessTreeResourceSample: Equatable {
    let rootPID: Int32
    let representativePID: Int32
    let representativeProcessGroupID: Int32?
    let processName: String
    let cpuTimeNanos: UInt64
    let memoryBytes: UInt64
    let threadCount: Int
}

extension ProcessResourceSampler {
    static func sampleProcessTree(rootPID: Int32) -> ProcessTreeResourceSample? {
        guard rootPID > 0 else { return nil }
        let parentPIDByPID = processParentPIDMap()
        let pids = descendantProcessIDs(rootPID: rootPID, parentPIDByPID: parentPIDByPID)
        let samples = pids.compactMap(sampleProcess(pid:))
        return aggregateProcessTree(rootPID: rootPID, samples: samples, parentPIDByPID: parentPIDByPID)
    }

    static func aggregateProcessTree(
        rootPID: Int32,
        samples: [ProcessResourceSample],
        parentPIDByPID: [Int32: Int32]
    ) -> ProcessTreeResourceSample? {
        guard !samples.isEmpty else { return nil }
        let descendants = Set(descendantProcessIDs(rootPID: rootPID, parentPIDByPID: parentPIDByPID))
        let treeSamples = samples.filter { descendants.contains($0.pid) }
        guard !treeSamples.isEmpty else { return nil }
        let representative = treeSamples.max { lhs, rhs in
            if lhs.pid == rootPID { return true }
            if rhs.pid == rootPID { return false }
            if lhs.cpuTimeNanos == rhs.cpuTimeNanos {
                return lhs.footprintBytes < rhs.footprintBytes
            }
            return lhs.cpuTimeNanos < rhs.cpuTimeNanos
        }
        guard let representative else { return nil }
        return ProcessTreeResourceSample(
            rootPID: rootPID,
            representativePID: representative.pid,
            representativeProcessGroupID: processGroupID(pid: representative.pid),
            processName: representative.processName,
            cpuTimeNanos: treeSamples.reduce(0) { $0 + $1.cpuTimeNanos },
            memoryBytes: treeSamples.reduce(0) { $0 + max($1.footprintBytes, $1.residentBytes) },
            threadCount: treeSamples.reduce(0) { $0 + $1.threadCount }
        )
    }

    static func descendantProcessIDs(rootPID: Int32, parentPIDByPID: [Int32: Int32]) -> [Int32] {
        guard rootPID > 0 else { return [] }
        var result: [Int32] = [rootPID]
        var visited: Set<Int32> = [rootPID]
        var stack: [Int32] = [rootPID]
        while let parent = stack.popLast() {
            for (pid, parentPID) in parentPIDByPID where parentPID == parent && !visited.contains(pid) {
                visited.insert(pid)
                result.append(pid)
                stack.append(pid)
            }
        }
        return result
    }

    private static func processParentPIDMap() -> [Int32: Int32] {
        let bytes = proc_listallpids(nil, 0)
        guard bytes > 0 else { return [:] }

        let pidStride = MemoryLayout<pid_t>.stride
        var buffer = [pid_t](repeating: 0, count: Int(bytes) / pidStride)
        let filled = proc_listallpids(&buffer, bytes)
        guard filled > 0 else { return [:] }

        var result: [Int32: Int32] = [:]
        for index in 0 ..< (Int(filled) / pidStride) {
            let pid = Int32(buffer[index])
            guard pid > 0, let parentPID = parentPID(pid: pid) else { continue }
            result[pid] = parentPID
        }
        return result
    }

    private static func parentPID(pid: Int32) -> Int32? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Int32(info.pbi_ppid)
    }

    private static func processGroupID(pid: Int32) -> Int32? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Int32(info.pbi_pgid)
    }
}
