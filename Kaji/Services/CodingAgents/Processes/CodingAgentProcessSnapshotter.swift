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
        let arguments = try CodingAgentProcessArgumentSnapshotter.arguments()
        return CodingAgentNativeProcessSnapshotter.snapshot(argumentsByPID: arguments)
    }
}
