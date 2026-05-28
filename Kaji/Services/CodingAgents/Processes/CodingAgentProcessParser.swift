import Foundation

enum CodingAgentProcessParser {
    static func parse(_ output: String) -> [CodingAgentProcessInfo] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .dropFirst()
            .compactMap(parseLine)
    }

    private static func parseLine(_ line: Substring) -> CodingAgentProcessInfo? {
        let fields = line.split(separator: " ", maxSplits: 6, omittingEmptySubsequences: true)
        guard fields.count == 7,
              let pid = Int32(fields[0]),
              let parentPID = Int32(fields[1]),
              let processGroupID = Int32(fields[2]),
              let cpuPercent = Double(fields[3]),
              let residentKB = UInt64(fields[4])
        else { return nil }

        return CodingAgentProcessInfo(
            pid: pid,
            parentPID: parentPID,
            processGroupID: processGroupID,
            cpuPercent: cpuPercent,
            memoryBytes: residentKB * 1024,
            commandName: URL(fileURLWithPath: String(fields[5])).lastPathComponent,
            commandLine: String(fields[6])
        )
    }
}
