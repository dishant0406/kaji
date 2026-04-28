import Darwin
import Foundation

struct ProcessResourceSample: Equatable {
    let pid: Int32
    let processName: String
    let cpuTimeNanos: UInt64
    let memoryBytes: UInt64
    let threadCount: Int
}

enum ProcessResourceSampler {
    static func sample(pid: Int32) -> ProcessResourceSample? {
        guard pid > 0 else { return nil }

        var taskInfo = proc_taskinfo()
        let expectedSize = Int32(MemoryLayout<proc_taskinfo>.size)
        let actualSize = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, expectedSize)
        guard actualSize == expectedSize else { return nil }

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
            cpuTimeNanos: UInt64(taskInfo.pti_total_user) + UInt64(taskInfo.pti_total_system),
            memoryBytes: taskInfo.pti_resident_size,
            threadCount: Int(taskInfo.pti_threadnum)
        )
    }
}
