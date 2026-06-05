import Foundation

enum CodingAgentCommandRunner {
    private static let timeout: TimeInterval = 10

    static func lines(executableName: String, arguments: [String]) -> [String] {
        let extraDirectories = CodingAgentRegistry.shared.definitions.first { definition in
            definition.executableNames.contains(executableName)
        }?.executableSearchDirectories ?? []
        guard let path = AIProviderExecutableLocator.resolvePath(
            for: executableName,
            extraDirectories: extraDirectories
        )
        else { return [] }
        return DispatchQueue.global(qos: .userInitiated).sync {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()

            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }

            do { try process.run() } catch { return [] }
            let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
            if timedOut {
                process.terminate()
                process.waitUntilExit()
                return []
            }

            guard process.terminationStatus == 0,
                  let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            else { return [] }
            return text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        }
    }
}
