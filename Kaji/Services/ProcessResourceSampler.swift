import Darwin
import Foundation

struct ProcessStartIdentity: Hashable {
    let seconds: UInt64
    let microseconds: UInt64
}

struct ProcessResourceSample: Equatable {
    let pid: Int32
    let parentPID: Int32
    let processGroupID: Int32
    let startIdentity: ProcessStartIdentity
    let processName: String
    let ttyName: String?
    let cpuTimeNanos: UInt64
    let residentBytes: UInt64
    let footprintBytes: UInt64
    let threadCount: Int

    init(
        pid: Int32,
        parentPID: Int32 = 0,
        processGroupID: Int32 = 0,
        startIdentity: ProcessStartIdentity = .init(seconds: 0, microseconds: 0),
        processName: String,
        ttyName: String? = nil,
        cpuTimeNanos: UInt64,
        residentBytes: UInt64,
        footprintBytes: UInt64,
        threadCount: Int
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.processGroupID = processGroupID
        self.startIdentity = startIdentity
        self.processName = processName
        self.ttyName = ttyName
        self.cpuTimeNanos = cpuTimeNanos
        self.residentBytes = residentBytes
        self.footprintBytes = footprintBytes
        self.threadCount = threadCount
    }

    var memoryBytes: UInt64 {
        max(footprintBytes, residentBytes)
    }
}

struct DarwinProcessTableSnapshot: Equatable {
    let processesByPID: [Int32: ProcessResourceSample]

    var processes: [ProcessResourceSample] {
        Array(processesByPID.values)
    }

    func process(pid: Int32) -> ProcessResourceSample? {
        processesByPID[pid]
    }
}

struct ProcessGroupResourceSample: Equatable {
    let processGroupID: Int32
    let representativePID: Int32
    let processName: String
    let cpuTimeNanos: UInt64
    let memoryBytes: UInt64
    let threadCount: Int
}

enum ProcessResourceSnapshotError: LocalizedError {
    case processListUnavailable

    var errorDescription: String? {
        switch self {
        case .processListUnavailable:
            "The Darwin process table is unavailable."
        }
    }
}

enum ProcessResourceSampler {
    static func snapshot() throws -> DarwinProcessTableSnapshot {
        let pidCapacity = proc_listallpids(nil, 0)
        guard pidCapacity > 0 else { throw ProcessResourceSnapshotError.processListUnavailable }

        let pidStride = MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: Int(pidCapacity) + 64)
        let filledCount = proc_listallpids(&pids, Int32(pids.count * pidStride))
        guard filledCount > 0 else { throw ProcessResourceSnapshotError.processListUnavailable }

        var processesByPID: [Int32: ProcessResourceSample] = [:]
        processesByPID.reserveCapacity(Int(filledCount))
        for rawPID in pids.prefix(Int(filledCount)) {
            let pid = Int32(rawPID)
            guard pid > 0, let sample = sampleProcess(pid: pid) else { continue }
            processesByPID[pid] = sample
        }
        return DarwinProcessTableSnapshot(processesByPID: processesByPID)
    }

    static func sampleCurrentProcess() -> ProcessResourceSample? {
        sampleProcess(pid: getpid())
    }

    static func samplesForProcessGroup(id: Int32) -> [ProcessResourceSample] {
        guard id > 0, let snapshot = try? snapshot() else { return [] }
        return snapshot.processes.filter { $0.processGroupID == id }
    }

    static func sampleProcessGroup(id: Int32) -> ProcessGroupResourceSample? {
        aggregate(processGroupID: id, samples: samplesForProcessGroup(id: id))
    }

    static func aggregate(
        processGroupID: Int32,
        samples: [ProcessResourceSample]
    ) -> ProcessGroupResourceSample? {
        guard !samples.isEmpty else { return nil }
        let representative = samples.first(where: { $0.pid == processGroupID }) ?? busiest(in: samples)
        guard let representative else { return nil }

        return ProcessGroupResourceSample(
            processGroupID: processGroupID,
            representativePID: representative.pid,
            processName: representative.processName,
            cpuTimeNanos: samples.reduce(0) { $0 + $1.cpuTimeNanos },
            memoryBytes: samples.reduce(0) { $0 + $1.memoryBytes },
            threadCount: samples.reduce(0) { $0 + $1.threadCount }
        )
    }

    static func sampleProcess(pid: Int32) -> ProcessResourceSample? {
        guard pid > 0 else { return nil }

        var bsdInfo = proc_bsdinfo()
        let bsdInfoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, bsdInfoSize) == bsdInfoSize else { return nil }

        var usage = rusage_info_current()
        let usageResult = withUnsafeMutablePointer(to: &usage) { pointer in
            let raw = UnsafeMutableRawPointer(pointer)
            let typed = raw.assumingMemoryBound(to: rusage_info_t?.self)
            return proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, typed)
        }
        guard usageResult == 0 else { return nil }

        var taskInfo = proc_taskinfo()
        let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.size)
        let actualTaskInfoSize = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskInfoSize)
        let threadCount = actualTaskInfoSize == taskInfoSize ? Int(taskInfo.pti_threadnum) : 0

        var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let processName = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0
            ? String(bytes: nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? "Process \(pid)"
            : "Process \(pid)"

        return ProcessResourceSample(
            pid: pid,
            parentPID: Int32(bsdInfo.pbi_ppid),
            processGroupID: Int32(bsdInfo.pbi_pgid),
            startIdentity: ProcessStartIdentity(
                seconds: bsdInfo.pbi_start_tvsec,
                microseconds: bsdInfo.pbi_start_tvusec
            ),
            processName: processName,
            ttyName: ttyName(from: bsdInfo),
            cpuTimeNanos: MachTimeConverter.toNanoseconds(usage.ri_user_time + usage.ri_system_time),
            residentBytes: usage.ri_resident_size,
            footprintBytes: usage.ri_phys_footprint,
            threadCount: threadCount
        )
    }

    static func foregroundProcessGroupID(ttyName: String?) -> Int32? {
        guard let path = validatedTTYPath(ttyName) else { return nil }
        let descriptor = open(path, O_RDONLY | O_NOCTTY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        let processGroupID = tcgetpgrp(descriptor)
        return processGroupID > 0 ? processGroupID : nil
    }

    static func validatedTTYPath(_ ttyName: String?) -> String? {
        guard let ttyName else { return nil }
        let component = ttyName.hasPrefix("/dev/") ? String(ttyName.dropFirst(5)) : ttyName
        guard component.hasPrefix("tty"),
              component.count <= 64,
              component.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) })
        else { return nil }
        return "/dev/\(component)"
    }

    private static func ttyName(from bsdInfo: proc_bsdinfo) -> String? {
        guard bsdInfo.pbi_flags & UInt32(PROC_FLAG_CONTROLT) != 0, bsdInfo.e_tdev != UInt32.max else { return nil }
        let device = dev_t(bitPattern: bsdInfo.e_tdev)
        guard let name = devname(device, S_IFCHR) else { return nil }
        let value = String(cString: name)
        return validatedTTYPath(value)
    }

    private static func busiest(in samples: [ProcessResourceSample]) -> ProcessResourceSample? {
        samples.max { lhs, rhs in
            if lhs.cpuTimeNanos == rhs.cpuTimeNanos {
                return lhs.memoryBytes < rhs.memoryBytes
            }
            return lhs.cpuTimeNanos < rhs.cpuTimeNanos
        }
    }
}
