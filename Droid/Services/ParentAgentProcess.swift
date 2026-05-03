import Foundation

@MainActor
final class ParentAgentProcess {
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputBuffer = Data()
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    var onMessage: ((ParentAgentEnvelope) -> Void)?
    var onError: ((String) -> Void)?

    func send(_ message: ParentAgentEnvelope) {
        do {
            try startIfNeeded()
            let data = try encoder.encode(message) + Data([10])
            inputPipe?.fileHandleForWriting.write(data)
        } catch {
            onError?(error.localizedDescription)
        }
    }

    private func startIfNeeded() throws {
        if process?.isRunning == true { return }
        guard let launch = Self.launch else {
            throw ParentAgentProcessError.scriptMissing
        }

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = launch.arguments
        process.currentDirectoryURL = launch.directory
        process.environment = ParentAgentSettingsStore.shared.launchEnvironment()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.consume(data) }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.onError?(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        try process.run()
        self.process = process
        self.inputPipe = inputPipe
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 10) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            do {
                onMessage?(try decoder.decode(ParentAgentEnvelope.self, from: Data(line)))
            } catch {
                onError?(error.localizedDescription)
            }
        }
    }

    private static var launch: ParentAgentLaunch? {
        if let source = sourceLaunch {
            return source
        }
        guard let script = bundledScriptURL else { return nil }
        return ParentAgentLaunch(arguments: ["node", script.path], directory: nil)
    }

    private static var sourceLaunch: ParentAgentLaunch? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let piRoot = root.appending(path: "External/pi-mono")
        let script = piRoot.appending(path: "packages/droid-agent/src/main.ts")
        let tsx = piRoot.appending(path: "node_modules/.bin/tsx")
        guard FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: tsx.path)
        else { return nil }
        return ParentAgentLaunch(arguments: [tsx.path, script.path], directory: piRoot)
    }

    private static var bundledScriptURL: URL? {
        Bundle.module.url(forResource: "droid-agent", withExtension: "mjs", subdirectory: "pi")
            ?? Bundle.main.url(forResource: "droid-agent", withExtension: "mjs", subdirectory: "pi")
            ?? bundledDevScriptURL
    }

    private static var bundledDevScriptURL: URL? {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Droid/Resources/pi/droid-agent.mjs")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

private struct ParentAgentLaunch {
    let arguments: [String]
    let directory: URL?
}

enum ParentAgentProcessError: LocalizedError {
    case scriptMissing

    var errorDescription: String? {
        "Droid parent agent script is missing."
    }
}
