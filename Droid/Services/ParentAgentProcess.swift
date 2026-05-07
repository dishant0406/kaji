import Foundation

@MainActor
final class ParentAgentProcess {
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputBuffer = Data()
    private var configurationSignature: String?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    var environmentOverrides: [String: String] = [:]
    var onMessage: ((ParentAgentEnvelope) -> Void)?
    var onError: ((String) -> Void)?

    func send(_ message: ParentAgentEnvelope) {
        do {
            try startIfNeeded()
            guard process?.isRunning == true else {
                onError?(ParentAgentSettingsStore.shared.readiness.detail)
                return
            }
            let data = try encoder.encode(message) + Data([10])
            inputPipe?.fileHandleForWriting.write(data)
        } catch {
            onError?(error.localizedDescription)
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        inputPipe = nil
        outputBuffer = Data()
        configurationSignature = nil
    }

    private func startIfNeeded() throws {
        var environment = ParentAgentSettingsStore.shared.launchEnvironment()
        environment.merge(environmentOverrides) { _, new in new }
        let signature = Self.configurationSignature(for: environment)
        if process?.isRunning == true, configurationSignature == signature { return }
        if process?.isRunning == true {
            stop()
        }
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
        process.environment = environment
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
        configurationSignature = signature
    }

    private static func configurationSignature(for environment: [String: String]) -> String {
        [
            environment["DROID_PARENT_PROVIDER"] ?? "",
            environment["DROID_PARENT_MODEL"] ?? "",
            environment["DROID_PARENT_THINKING"] ?? "",
            environment["DROID_PARENT_AGENT_MODE"] ?? "",
            environment["GRAPHIFY_OUT"] ?? "",
            environment["DROID_GRAPH_READ_ROOTS"] ?? "",
            environment["DROID_GRAPH_WRITE_ROOTS"] ?? "",
            environment["DROID_GRAPH_SHELL_ROOTS"] ?? "",
        ].joined(separator: "\u{1f}")
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 10) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            do {
                try onMessage?(decoder.decode(ParentAgentEnvelope.self, from: Data(line)))
            } catch {
                onError?(error.localizedDescription)
            }
        }
    }

    private static var launch: ParentAgentLaunch? {
        guard ParentAgentSettingsStore.shared.readiness.isReady else { return nil }
        if let source = ParentAgentRuntimeLocator.sourceLaunch() {
            return source
        }
        return ParentAgentRuntimeLocator.bundledLaunch()
    }
}

enum ParentAgentProcessError: LocalizedError {
    case scriptMissing

    var errorDescription: String? {
        "Droid parent agent script is missing."
    }
}
