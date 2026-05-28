import Foundation

enum PortProcessListError: LocalizedError {
    case commandFailed(String)
    case unreadableOutput

    var errorDescription: String? {
        switch self {
        case let .commandFailed(message):
            message.isEmpty ? "Unable to list running ports." : message
        case .unreadableOutput:
            "Unable to read running ports."
        }
    }
}

enum PortProcessLister {
    static func list() async throws -> [PortProcessSnapshot] {
        try await Task.detached(priority: .utility) {
            try listSync()
        }.value
    }

    private static func listSync() throws -> [PortProcessSnapshot] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN"]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? ""
            throw PortProcessListError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard let text = String(data: outputData, encoding: .utf8) else {
            throw PortProcessListError.unreadableOutput
        }

        return PortProcessParser.parse(text)
    }
}
