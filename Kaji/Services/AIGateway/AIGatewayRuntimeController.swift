import Darwin
import Foundation

@MainActor
@Observable
final class AIGatewayRuntimeController {
    static let shared = AIGatewayRuntimeController()

    private(set) var status: AIGatewayRuntimeStatus = .stopped
    private(set) var recentLogs: [String] = []

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var stdoutPipe: Pipe?
    @ObservationIgnored private var stderrPipe: Pipe?
    @ObservationIgnored private let healthClient = AIGatewayHealthClient()
    @ObservationIgnored private let portReclaimer = AIGatewayPortReclaimer()

    var isRunning: Bool {
        if case .running = status {
            return true
        }
        return false
    }

    func refreshInstallState() {
        if case .installed = AIGatewayClaudeCodeRouterInstaller.state() {
            if process?.isRunning == true {
                return
            }
            status = .stopped
        } else {
            status = .notInstalled
        }
    }

    func start(settings: AIGatewaySettings, token: String) async {
        guard !token.isEmpty else {
            status = .failed("Gateway token is missing.")
            return
        }
        if let message = AIGatewayConfigValidator.validate(settings) {
            status = .failed(message)
            return
        }
        if process?.isRunning == true {
            return
        }
        recentLogs.removeAll()
        let installResult = await Task.detached { AIGatewayClaudeCodeRouterInstaller.ensureCurrent() }.value
        guard case .installed = installResult.state else {
            status = .failed(installResult.message)
            return
        }
        status = .starting
        do {
            _ = try AIGatewayClaudeCodeRouterConfigWriter.write(settings: settings, token: token)
            applyEnabledConnectors(settings: settings)
            try await reclaimPorts(settings: settings)
            try launch(settings: settings, environment: launchEnvironment(settings: settings, token: token))
            await waitForHealth(endpoint: settings.endpointBaseURL)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func stop() {
        guard let process else {
            status = .stopped
            return
        }
        process.terminate()
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        clearPipes()
        self.process = nil
        status = .stopped
    }

    func restart(settings: AIGatewaySettings, token: String) async {
        stop()
        await start(settings: settings, token: token)
    }

    private func launch(settings: AIGatewaySettings, environment: [String: String]) throws {
        let process = Process()
        process.executableURL = AIGatewayClaudeCodeRouterPaths.commandURL()
        process.arguments = launchArguments(settings: settings)
        process.currentDirectoryURL = AIGatewayStoragePaths.supportDirectory()
        var env = TerminalEnvironmentPolicy.sanitizedEnvironment(from: ProcessInfo.processInfo.environment)
        env.merge(environment) { _, new in new }
        process.environment = env
        attachPipes(to: process)
        process.terminationHandler = { [weak self] terminated in
            Task { @MainActor in
                self?.handleExit(status: terminated.terminationStatus)
            }
        }
        try process.run()
        self.process = process
        appendLog("AI Gateway started on \(settings.serverBind).")
    }

    private func reclaimPorts(settings: AIGatewaySettings) async throws {
        let ports = [settings.normalizedPort, min(settings.normalizedPort + 1, 65535), managementPort(settings)]
        for port in ports {
            let result = try await portReclaimer.reclaim(port: port)
            appendReclaimLog(result, port: port)
        }
    }

    private func applyEnabledConnectors(settings: AIGatewaySettings) {
        do {
            if settings.claudeConnectorEnabled {
                try AIGatewayClaudeConnector.install(settings: settings)
            }
            if settings.codexConnectorEnabled {
                try AIGatewayCodexConnector.install(settings: settings)
            }
        } catch {
            appendLog("Failed to refresh AI Gateway client config: \(error.localizedDescription)")
        }
    }

    private func waitForHealth(endpoint: String) async {
        for _ in 0 ..< 30 {
            if await healthClient.isHealthy(endpoint: endpoint) {
                status = .running(endpoint)
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        status = .failed("AI Gateway did not pass health check.")
    }

    private func attachPipes(to process: Process) {
        let stdout = Pipe()
        let stderr = Pipe()
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.appendLog(String(data: data, encoding: .utf8) ?? "") }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.appendLog(String(data: data, encoding: .utf8) ?? "") }
        }
        process.standardOutput = stdout
        process.standardError = stderr
        stdoutPipe = stdout
        stderrPipe = stderr
    }

    private func handleExit(status exitStatus: Int32) {
        clearPipes()
        process = nil
        guard exitStatus == 0 else {
            status = .failed("AI Gateway exited with status \(exitStatus).")
            return
        }
        status = .stopped
    }

    private func appendReclaimLog(_ result: AIGatewayPortReclaimResult, port: Int) {
        guard !result.isEmpty else { return }
        appendLog("Cleared \(result.count) process(es) from port \(port).")
    }

    private func appendLog(_ raw: String) {
        let lines = raw.components(separatedBy: .newlines).map(AIGatewayRedactor.redact).filter { !$0.isEmpty }
        recentLogs.append(contentsOf: lines)
        if recentLogs.count > 80 {
            recentLogs.removeFirst(recentLogs.count - 80)
        }
    }

    private func clearPipes() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
    }
}
