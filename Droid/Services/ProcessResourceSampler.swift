import Darwin
import Foundation

struct ProcessResourceSample: Equatable {
    let pid: Int32
    let processName: String
    let cpuTimeNanos: UInt64
    let residentBytes: UInt64
    let footprintBytes: UInt64
    let threadCount: Int
}

struct ProcessGroupResourceSample: Equatable {
    let processGroupID: Int32
    let representativePID: Int32
    let processName: String
    let cpuTimeNanos: UInt64
    let memoryBytes: UInt64
    let threadCount: Int
}

enum ProcessResourceSampler {
    static func sampleCurrentProcess() -> ProcessResourceSample? {
        sampleProcess(pid: getpid())
    }

    static func samplesForProcessGroup(id: Int32) -> [ProcessResourceSample] {
        guard id > 0 else { return [] }
        return processGroupPIDs(id).compactMap(sampleProcess(pid:))
    }

    static func sampleProcessGroup(id: Int32) -> ProcessGroupResourceSample? {
        let samples = samplesForProcessGroup(id: id)
        return aggregate(processGroupID: id, samples: samples)
    }

    static func aggregate(
        processGroupID: Int32,
        samples: [ProcessResourceSample]
    ) -> ProcessGroupResourceSample? {
        guard !samples.isEmpty else { return nil }

        let representative =
            samples.first(where: { $0.pid == processGroupID })
                ?? samples.max { lhs, rhs in
                    if lhs.cpuTimeNanos == rhs.cpuTimeNanos {
                        return lhs.footprintBytes < rhs.footprintBytes
                    }
                    return lhs.cpuTimeNanos < rhs.cpuTimeNanos
                }

        guard let representative else { return nil }

        return ProcessGroupResourceSample(
            processGroupID: processGroupID,
            representativePID: representative.pid,
            processName: representative.processName,
            cpuTimeNanos: samples.reduce(0) { $0 + $1.cpuTimeNanos },
            memoryBytes: samples.reduce(0) { $0 + max($1.footprintBytes, $1.residentBytes) },
            threadCount: samples.reduce(0) { $0 + $1.threadCount }
        )
    }

    private static func sampleProcess(pid: Int32) -> ProcessResourceSample? {
        guard pid > 0 else { return nil }

        var usage = rusage_info_current()
        let usageResult = withUnsafeMutablePointer(to: &usage) { pointer in
            let raw = UnsafeMutableRawPointer(pointer)
            let typed = raw.assumingMemoryBound(to: rusage_info_t?.self)
            return proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, typed)
        }
        guard usageResult == 0 else { return nil }

        var taskInfo = proc_taskinfo()
        let expectedSize = Int32(MemoryLayout<proc_taskinfo>.size)
        let actualSize = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, expectedSize)
        let threadCount = actualSize == expectedSize ? Int(taskInfo.pti_threadnum) : 0

        var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let processName = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0
            ? String(
                bytes: nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                encoding: .utf8
            ) ?? "Process \(pid)"
            : "Process \(pid)"

        return ProcessResourceSample(
            pid: pid,
            processName: processName,
            cpuTimeNanos: MachTimeConverter.toNanoseconds(usage.ri_user_time + usage.ri_system_time),
            residentBytes: usage.ri_resident_size,
            footprintBytes: usage.ri_phys_footprint,
            threadCount: threadCount
        )
    }

    private static func processGroupPIDs(_ processGroupID: Int32) -> [Int32] {
        let bytes = proc_listpids(UInt32(PROC_PGRP_ONLY), UInt32(processGroupID), nil, 0)
        guard bytes > 0 else { return [] }

        let pidStride = MemoryLayout<pid_t>.stride
        var buffer = [pid_t](repeating: 0, count: Int(bytes) / pidStride)
        let filled = proc_listpids(UInt32(PROC_PGRP_ONLY), UInt32(processGroupID), &buffer, bytes)
        guard filled > 0 else { return [] }

        let count = Int(filled) / pidStride
        var pids: [Int32] = []
        pids.reserveCapacity(count)

        for index in 0 ..< count {
            let pid = Int32(buffer[index])
            if pid > 0 {
                pids.append(pid)
            }
        }

        return pids
    }
}
