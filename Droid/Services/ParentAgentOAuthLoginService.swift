import AppKit
import Foundation

@MainActor
@Observable
final class ParentAgentOAuthLoginService {
    static let shared = ParentAgentOAuthLoginService()

    var isRunning = false
    var statusMessage = ""
    var promptMessage: String?
    var promptPlaceholder = ""
    var promptValue = ""

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputBuffer = Data()
    private var pendingPromptID: String?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private init() {}

    func login(provider: ParentAgentProvider) {
        guard let oauthKey = provider.oauthKey, !isRunning else { return }
        do {
            let launch = try launchConfiguration(providerID: oauthKey)
            isRunning = true
            statusMessage = "Starting login."
            promptMessage = nil
            promptPlaceholder = ""
            promptValue = ""
            pendingPromptID = nil
            outputBuffer = Data()

            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = launch.arguments
            process.currentDirectoryURL = launch.directory
            var environment = ProcessInfo.processInfo.environment
            environment.removeValue(forKey: "NODE_TLS_REJECT_UNAUTHORIZED")
            process.environment = environment
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.terminationHandler = { [weak self] _ in
                Task { @MainActor in
                    self?.isRunning = false
                    ParentAgentSettingsStore.shared.refreshAuthStatus()
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
                Task { @MainActor in self?.statusMessage = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            try process.run()
            self.process = process
            self.inputPipe = inputPipe
        } catch {
            statusMessage = error.localizedDescription
            isRunning = false
        }
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 10) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            handle(line: Data(line))
        }
    }

    private func handle(line: Data) {
        do {
            let message = try decoder.decode(ParentAgentOAuthMessage.self, from: line)
            switch message.type {
            case "oauth_auth":
                statusMessage = message.message ?? "Complete login in your browser."
                if let urlString = message.url, let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            case "oauth_prompt":
                pendingPromptID = message.id
                promptMessage = message.message ?? "Paste the authorization code or redirect URL:"
                promptPlaceholder = message.placeholder ?? ""
                promptValue = ""
            case "oauth_complete":
                statusMessage = message.message ?? "Connected."
                promptMessage = nil
                pendingPromptID = nil
                ParentAgentSettingsStore.shared.refreshAuthStatus()
            case "oauth_error":
                statusMessage = message.message ?? "OAuth failed."
            default:
                statusMessage = message.message ?? statusMessage
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func submitPromptValue() {
        guard let pendingPromptID else { return }
        do {
            let message = ParentAgentOAuthPromptResponse(
                type: "oauth_prompt_response",
                id: pendingPromptID,
                value: promptValue
            )
            inputPipe?.fileHandleForWriting.write(try encoder.encode(message) + Data([10]))
            promptMessage = nil
            self.pendingPromptID = nil
            promptValue = ""
            statusMessage = "Continuing login."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func launchConfiguration(providerID: String) throws -> ParentAgentOAuthLaunch {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let piRoot = root.appending(path: "Vendor/pi-mono")
        let script = piRoot.appending(path: "packages/droid-agent/src/oauth-login.ts")
        let tsx = piRoot.appending(path: "node_modules/.bin/tsx")
        guard FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: tsx.path)
        else { throw ParentAgentOAuthLoginError.helperMissing }
        return ParentAgentOAuthLaunch(arguments: [tsx.path, script.path, providerID], directory: piRoot)
    }
}

private struct ParentAgentOAuthMessage: Codable {
    let type: String
    let id: String?
    let url: String?
    let message: String?
    let placeholder: String?
}

private struct ParentAgentOAuthPromptResponse: Codable {
    let type: String
    let id: String
    let value: String
}

private struct ParentAgentOAuthLaunch {
    let arguments: [String]
    let directory: URL
}

private enum ParentAgentOAuthLoginError: LocalizedError {
    case helperMissing

    var errorDescription: String? {
        "Droid OAuth helper is missing."
    }
}
