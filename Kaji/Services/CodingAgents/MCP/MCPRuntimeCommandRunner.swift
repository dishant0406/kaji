import Foundation

enum MCPRuntimeCommandRunner {
    static func run(
        executableName: String,
        arguments: [String],
        projectPath: String?,
        homeDirectory: String,
        timeout: TimeInterval = 1.5
    ) -> String? {
        guard ProcessInfo.processInfo.environment["KAJI_MCP_RUNTIME_SCAN"] == "1" else { return nil }
        guard let path = AIProviderExecutableLocator.resolvePath(for: executableName, homeDirectory: homeDirectory) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        if let projectPath { process.currentDirectoryURL = URL(fileURLWithPath: projectPath) }

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        }
        return text
    }
}
