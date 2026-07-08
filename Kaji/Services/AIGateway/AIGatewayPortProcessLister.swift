import Foundation

protocol AIGatewayPortProcessListing: Sendable {
    func list(port: Int) async throws -> [PortProcessSnapshot]
}

struct AIGatewayPortProcessLister: AIGatewayPortProcessListing {
    func list(port: Int) async throws -> [PortProcessSnapshot] {
        try await Task.detached(priority: .utility) {
            try Self.listSync(port: port)
        }.value
    }

    private static func listSync(port: Int) throws -> [PortProcessSnapshot] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            let message = String(data: errorData, encoding: .utf8) ?? ""
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if outputData.isEmpty, trimmedMessage.isEmpty { return [] }
            throw PortProcessListError.commandFailed(trimmedMessage)
        }

        guard let text = String(data: outputData, encoding: .utf8) else {
            throw PortProcessListError.unreadableOutput
        }

        return PortProcessParser.parse(text).filter { $0.port == port }
    }
}
