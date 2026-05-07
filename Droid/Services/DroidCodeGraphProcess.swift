import Foundation

struct DroidCodeGraphProcessResult: Equatable {
    let status: Int32
    let stdout: String
    let stderr: String
}

protocol DroidCodeGraphProcessRunning: Sendable {
    func run(
        executable: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String]
    ) async throws -> DroidCodeGraphProcessResult
}

struct DroidCodeGraphProcessRunner: DroidCodeGraphProcessRunning {
    func run(
        executable: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String]
    ) async throws -> DroidCodeGraphProcessResult {
        try await GitProcessRunner.offMainThrowing {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            }
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let outputText = String(data: outputData, encoding: .utf8) ?? ""
            return DroidCodeGraphProcessResult(
                status: process.terminationStatus,
                stdout: outputText,
                stderr: ""
            )
        }
    }
}
