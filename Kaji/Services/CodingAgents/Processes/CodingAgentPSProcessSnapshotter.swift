import Foundation

enum CodingAgentPSProcessSnapshotter {
    static func snapshot() throws -> [CodingAgentProcessInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,pgid=,stat=,tty=,pcpu=,rss=,comm=,args="]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        let outputCollector = ProcessPipeCollector(pipe: output)
        let errorCollector = ProcessPipeCollector(pipe: error)
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        try process.run()

        guard finished.wait(timeout: .now() + 5) == .success else {
            process.terminate()
            outputCollector.stop()
            errorCollector.stop()
            throw CodingAgentProcessSnapshotError.timedOut
        }

        outputCollector.stop()
        errorCollector.stop()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorCollector.data, encoding: .utf8) ?? ""
            throw CodingAgentProcessSnapshotError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard let text = String(data: outputCollector.data, encoding: .utf8) else {
            throw CodingAgentProcessSnapshotError.unreadableOutput
        }

        return parse(text)
    }

    static func parse(_ output: String) -> [CodingAgentProcessInfo] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap(parseLine)
    }

    private static func parseLine(_ line: Substring) -> CodingAgentProcessInfo? {
        let fields = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
        guard fields.count == 9,
              let pid = Int32(fields[0]),
              let parentPID = Int32(fields[1]),
              let processGroupID = Int32(fields[2]),
              let cpuPercent = Double(fields[5]),
              let residentKB = UInt64(fields[6])
        else { return nil }

        return CodingAgentProcessInfo(
            pid: pid,
            parentPID: parentPID,
            processGroupID: processGroupID,
            state: String(fields[3]),
            tty: String(fields[4]),
            cpuPercent: cpuPercent,
            memoryBytes: residentKB * 1024,
            threadCount: 0,
            commandName: URL(fileURLWithPath: String(fields[7])).lastPathComponent,
            executablePath: String(fields[7]),
            commandLine: String(fields[8])
        )
    }
}
