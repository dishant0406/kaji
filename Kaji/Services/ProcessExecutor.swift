import Foundation

enum ProcessExecutor {
    static func runSync(executableURL: URL, arguments: [String], currentDirectoryURL: URL) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "NODE_TLS_REJECT_UNAUTHORIZED")
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        let error = Pipe()
        let errorCollector = ProcessPipeCollector(pipe: error)
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        errorCollector.stop()
        guard process.terminationStatus == 0 else {
            throw FFFSearchError.processFailed(String(data: errorCollector.data, encoding: .utf8) ?? "")
        }
    }
}

enum FFFSearchError: LocalizedError {
    case processFailed(String)
    case workerUnavailable
    case workerTimedOut
    case invalidWorkerResponse

    var errorDescription: String? {
        switch self {
        case let .processFailed(message):
            message.isEmpty ? "FFF search failed" : message
        case .workerUnavailable:
            "Search service is temporarily unavailable"
        case .workerTimedOut:
            "Search service timed out"
        case .invalidWorkerResponse:
            "Search service returned an invalid response"
        }
    }
}
