import Foundation

enum CodingAgentCommandRunner {
    static func lines(executableName: String, arguments: [String]) -> [String] {
        let extraDirectories = CodingAgentRegistry.shared.definitions.first { definition in
            definition.executableNames.contains(executableName)
        }?.executableSearchDirectories ?? []
        guard let path = AIProviderExecutableLocator.resolvePath(
            for: executableName,
            extraDirectories: extraDirectories
        )
        else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { return [] }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        else { return [] }
        return text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}
