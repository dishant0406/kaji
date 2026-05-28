import Foundation

enum CodingAgentProcessSnapshotError: LocalizedError {
    case commandFailed(String)
    case unreadableOutput
    case timedOut

    var errorDescription: String? {
        switch self {
        case let .commandFailed(message):
            message.isEmpty ? "Unable to list agent processes." : message
        case .unreadableOutput:
            "Unable to read agent processes."
        case .timedOut:
            "Timed out while scanning agent processes."
        }
    }
}

enum CodingAgentProcessSnapshotter {
    static func snapshot() async throws -> [CodingAgentProcessInfo] {
        try await Task.detached(priority: .utility) {
            try snapshotSync()
        }.value
    }

    private static func snapshotSync() throws -> [CodingAgentProcessInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,pgid=,pcpu=,rss=,comm=,args="]

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

        let outputData = outputCollector.data
        let errorData = errorCollector.data

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? ""
            throw CodingAgentProcessSnapshotError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard let text = String(data: outputData, encoding: .utf8) else {
            throw CodingAgentProcessSnapshotError.unreadableOutput
        }

        return CodingAgentProcessParser.parse("HEADER\n" + text)
    }
}
