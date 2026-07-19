import Foundation

@MainActor
final class KajiAgentProcess {
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var outputBuffer = Data()
    private var configurationSignature: String?
    private var processID: UUID?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    var environmentOverrides: [String: String] = [:]
    var projectPath: String?
    var sessionDirectory: String?
    var approvalMode: String = KajiAgentPermissionMode.readAllow.rawValue
    var launch: KajiAgentLaunch?
    var onMessage: ((KajiAgentRPCFrame) -> Void)?
    var onError: ((String) -> Void)?

    func send(_ frame: KajiAgentRPCFrame) {
        do {
            try startIfNeeded()
            guard process?.isRunning == true else {
                onError?("Kaji Agent runtime is not running.")
                return
            }
            KajiAgentEventLog.recordFrame(frame, direction: "out")
            let data = try encoder.encode(frame) + Data([10])
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
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "NODE_TLS_REJECT_UNAUTHORIZED")
        environment["KAJI_AGENT_DIR"] = KajiFileStorage.appSupportDirectory()
            .appendingPathComponent("AgentRuntime", isDirectory: true)
            .path
        environment["KAJI_AGENT_ENABLE_MCP"] = environment["KAJI_AGENT_ENABLE_MCP"] ?? "0"
        environment["KAJI_AGENT_ENABLE_AUTORESEARCH"] = environment["KAJI_AGENT_ENABLE_AUTORESEARCH"] ?? "0"
        if let zlob = KajiAgentZlobLocator.executableURL() {
            environment["KAJI_ZLOB_BIN"] = zlob.path
        }
        environment.merge(environmentOverrides) { _, new in new }
        environment = PowerAssertionLaunchEnvironment.applyingAppOwnership(
            to: environment,
            assertionIsActive: SleepPreventionController.shared.verifyAssertionOwnership()
        )
        let signature = configurationSignature(for: environment)
        if process?.isRunning == true, configurationSignature == signature { return }
        if process?.isRunning == true { stop() }
        guard let launch else {
            throw KajiAgentProcessError.launchNotResolved
        }

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
            Task { @MainActor [weak self] in self?.cleanupProcess(id: processID) }
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
        KajiAgentEventLog.record("process_start", fields: [
            "logPath": .string(KajiAgentEventLog.path),
            "projectPath": .string(projectPath ?? ""),
            "arguments": .array(launch.arguments.map(KajiAgentJSONValue.string)),
        ])
        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
        self.processID = processID
        configurationSignature = signature
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
    }

    private func configurationSignature(for environment: [String: String]) -> String {
        [
            projectPath ?? "",
            sessionDirectory ?? "",
            approvalMode,
            environment["KAJI_AGENT_DIR"] ?? "",
            environment["KAJI_AGENT_ENABLE_MCP"] ?? "",
            environment["KAJI_AGENT_ENABLE_AUTORESEARCH"] ?? "",
            environment["KAJI_AGENT_ENABLE_MOCK"] ?? "",
            environment["KAJI_ZLOB_BIN"] ?? "",
            environment[PowerAssertionLaunchEnvironment.ownershipKey] ?? "",
            launch?.signature ?? "",
        ].joined(separator: "\u{1f}")
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 10) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            do {
                let frame = try decoder.decode(KajiAgentRPCFrame.self, from: Data(line))
                KajiAgentEventLog.recordFrame(frame, direction: "in")
                onMessage?(frame)
            } catch {
                let preview = String(data: Data(line.prefix(600)), encoding: .utf8) ?? "unreadable runtime event"
                KajiAgentEventLog.record("decode_error", fields: ["preview": .string(preview)])
                onError?("Failed to decode runtime event: \(preview)")
            }
        }
    }
}

enum KajiAgentProcessError: LocalizedError {
    case launchNotResolved

    var errorDescription: String? {
        "Kaji Agent runtime launch is not ready yet."
    }
}
