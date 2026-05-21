import Foundation

@MainActor
final class ParentAgentProcess {
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var outputBuffer = Data()
    private var configurationSignature: String?
    private var processID: UUID?
    private var launchStartDate: Date?
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
        cleanupProcess()
    }

    private func startIfNeeded() throws {
        let start = Date()
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
        DebugFileLog.log("ParentAgent", "launch starting args=\(launch.arguments.first ?? "")")

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let process = Process()
        let processID = UUID()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = launch.arguments
        process.currentDirectoryURL = launch.directory
        process.environment = environment
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cleanupProcess(id: processID)
            }
        }
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
        launchStartDate = start
        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
        self.processID = processID
        configurationSignature = signature
        DebugFileLog.log("ParentAgent", "launch completed duration=\(Date().timeIntervalSince(start))")
    }

    private func cleanupProcess(id: UUID? = nil) {
        if let id, processID != id { return }
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        outputBuffer = Data()
        configurationSignature = nil
        processID = nil
        launchStartDate = nil
    }

    private static func configurationSignature(for environment: [String: String]) -> String {
        [
            environment["KAJI_PARENT_PROVIDER"] ?? "",
            environment["KAJI_PARENT_MODEL"] ?? "",
            environment["KAJI_PARENT_THINKING"] ?? "",
            environment["KAJI_PARENT_AGENT_MODE"] ?? "",
            environment["GRAPHIFY_OUT"] ?? "",
            environment["KAJI_GRAPH_READ_ROOTS"] ?? "",
            environment["KAJI_GRAPH_WRITE_ROOTS"] ?? "",
            environment["KAJI_GRAPH_SHELL_ROOTS"] ?? "",
        ].joined(separator: "\u{1f}")
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 10) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            do {
                let message = try decoder.decode(ParentAgentEnvelope.self, from: Data(line))
                if message.type == "heartbeat", let launchStartDate {
                    DebugFileLog.log("ParentAgent", "heartbeat received duration=\(Date().timeIntervalSince(launchStartDate))")
                }
                onMessage?(message)
            } catch {
                onError?(error.localizedDescription)
            }
        }
    }

    private static var launch: ParentAgentLaunch? {
        guard ParentAgentSettingsStore.shared.isEnabled else { return nil }
        if let source = ParentAgentRuntimeLocator.sourceLaunch() {
            return source
        }
        return ParentAgentRuntimeLocator.bundledLaunch()
    }
}

enum ParentAgentProcessError: LocalizedError {
    case scriptMissing

    var errorDescription: String? {
        "Kaji parent agent script is missing."
    }
}
