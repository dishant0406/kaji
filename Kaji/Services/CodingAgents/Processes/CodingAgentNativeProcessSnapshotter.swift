import Darwin
import Foundation

enum CodingAgentNativeProcessSnapshotter {
    static func enrich(_ processes: [CodingAgentProcessInfo]) -> [CodingAgentProcessInfo] {
        let nativeByPID = Dictionary(uniqueKeysWithValues: snapshot(argumentsByPID: [:]).map { ($0.pid, $0) })
        return processes.map { process in
            guard let native = nativeByPID[process.pid] else { return process }
            return CodingAgentProcessInfo(
                pid: process.pid,
                parentPID: process.parentPID,
                processGroupID: process.processGroupID,
                state: process.state,
                tty: process.tty,
                cpuPercent: process.cpuPercent,
                memoryBytes: native.memoryBytes > 0 ? native.memoryBytes : process.memoryBytes,
                threadCount: native.threadCount,
                commandName: process.commandName,
                executablePath: native.executablePath ?? process.executablePath,
                commandLine: process.commandLine
            )
        }
    }

    static func snapshot(argumentsByPID: [Int32: String]) -> [CodingAgentProcessInfo] {
        processIDs().compactMap { processInfo(pid: $0, argumentsByPID: argumentsByPID) }
    }

    private static func processIDs() -> [Int32] {
        let bytes = proc_listallpids(nil, 0)
        guard bytes > 0 else { return [] }

        let stride = MemoryLayout<pid_t>.stride
        var buffer = [pid_t](repeating: 0, count: Int(bytes) / stride)
        let filled = proc_listallpids(&buffer, bytes)
        guard filled > 0 else { return [] }

        return (0 ..< (Int(filled) / stride))
            .map { Int32(buffer[$0]) }
            .filter { $0 > 0 }
    }

    private static func processInfo(pid: Int32, argumentsByPID: [Int32: String]) -> CodingAgentProcessInfo? {
        var bsdInfo = proc_bsdinfo()
        let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, bsdSize) == bsdSize else { return nil }

        var taskInfo = proc_taskinfo()
        let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
        let taskResult = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskSize)

        let executablePath = path(pid: pid)
        let commandName = name(path: executablePath, pid: pid)
        let commandLine = argumentsByPID[pid] ?? executablePath ?? commandName

        return CodingAgentProcessInfo(
            pid: pid,
            parentPID: Int32(bsdInfo.pbi_ppid),
            processGroupID: Int32(bsdInfo.pbi_pgid),
            state: state(from: bsdInfo.pbi_status),
            tty: "??",
            cpuPercent: 0,
            memoryBytes: taskResult == taskSize ? UInt64(taskInfo.pti_resident_size) : 0,
            threadCount: taskResult == taskSize ? Int(taskInfo.pti_threadnum) : 0,
            commandName: commandName,
            executablePath: executablePath,
            commandLine: commandLine
        )
    }

    private static func path(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard hasPath(pid: pid, buffer: &buffer) else { return nil }
        return string(from: buffer)
    }

    private static func name(path: String?, pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if proc_name(pid, &buffer, UInt32(buffer.count)) > 0,
           let command = string(from: buffer),
           !command.isEmpty
        {
            return command
        }
        if let path {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return "Process \(pid)"
    }

    private static func state(from status: UInt32) -> String {
        switch status {
        case UInt32(SIDL): "idle"
        case UInt32(SRUN): "running"
        case UInt32(SSLEEP): "sleeping"
        case UInt32(SSTOP): "stopped"
        case UInt32(SZOMB): "zombie"
        default: "unknown"
        }
    }

    private static func string(from buffer: [CChar]) -> String? {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        guard !bytes.isEmpty else { return nil }
        return String(bytes: bytes, encoding: .utf8)
    }

    private static func hasPath(pid: Int32, buffer: inout [CChar]) -> Bool {
        proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0
    }
}
