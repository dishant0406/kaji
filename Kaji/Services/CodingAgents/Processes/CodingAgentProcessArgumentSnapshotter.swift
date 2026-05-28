import Foundation

enum CodingAgentProcessArgumentSnapshotter {
    static func arguments() throws -> [Int32: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,args="]

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

    static func parse(_ output: String) -> [Int32: String] {
        var result: [Int32: String] = [:]
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard fields.count == 2, let pid = Int32(fields[0]) else { continue }
            result[pid] = String(fields[1])
        }
        return result
    }
}
