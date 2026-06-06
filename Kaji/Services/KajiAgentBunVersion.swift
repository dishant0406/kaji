import Foundation

struct KajiAgentBunVersion: Comparable, Equatable {
    let rawValue: String?
    let major: Int
    let minor: Int
    let patch: Int

    init(_ value: String? = nil) {
        rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = (rawValue ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "v \n\t"))
            .split(separator: ".")
            .map { Int($0.prefix { $0.isNumber }) ?? 0 }
        major = parts.indices.contains(0) ? parts[0] : 0
        minor = parts.indices.contains(1) ? parts[1] : 0
        patch = parts.indices.contains(2) ? parts[2] : 0
    }

    var supportsKajiAgentRuntime: Bool {
        self >= KajiAgentBunVersion("1.3.14")
    }

    static func read(at path: String) -> KajiAgentBunVersion {
        guard FileManager.default.isExecutableFile(atPath: path) else { return KajiAgentBunVersion() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var exitCode: Int32 = -1
        nonisolated(unsafe) var outputData = Data()
        do {
            try process.run()
        } catch {
            return KajiAgentBunVersion()
        }
        process.terminationHandler = { proc in
            exitCode = proc.terminationStatus
            outputData = output.fileHandleForReading.readDataToEndOfFile()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 3)
        if process.isRunning {
            process.terminate()
            return KajiAgentBunVersion()
        }
        guard exitCode == 0 else { return KajiAgentBunVersion() }
        return KajiAgentBunVersion(String(data: outputData, encoding: .utf8))
    }

    static func < (lhs: KajiAgentBunVersion, rhs: KajiAgentBunVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
