import Foundation

enum ProcessExecutor {
    static func runSync(executableURL: URL, arguments: [String], currentDirectoryURL: URL) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = Pipe()
        let error = Pipe()
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = error.fileHandleForReading.readDataToEndOfFile()
            throw FFFSearchError.processFailed(String(data: data, encoding: .utf8) ?? "")
        }
    }
}

enum FFFSearchError: LocalizedError {
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case let .processFailed(message):
            message.isEmpty ? "FFF search failed" : message
        }
    }
}
