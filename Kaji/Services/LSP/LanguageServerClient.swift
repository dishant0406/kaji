import Foundation

@MainActor
final class LanguageServerClient {
    let definition: LanguageDefinition
    let projectPath: String

    private var process: Process?
    private var stdin: FileHandle?
    private var buffer = Data()
    private var requestID = 0
    private var documentVersions: [String: Int] = [:]
    private var isInitialized = false
    private var pendingMessages: [(id: Int?, method: String, params: JSONValue)] = []
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(definition: LanguageDefinition, projectPath: String) {
        self.definition = definition
        self.projectPath = projectPath
    }

    func start() {
        guard process == nil, let lsp = definition.lsp else { return }
        guard let executable = LanguageServerExecutableResolver.executablePath(for: lsp.command) else {
            LanguageServerInstallPrompter.promptIfNeeded(definition: definition, projectPath: projectPath) { [weak self] in
                self?.start()
            }
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = lsp.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        stdin = input.fileHandleForWriting

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.receive(data) }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }

        do {
            try process.run()
            self.process = process
            initialize()
        } catch {
            stop()
        }
    }

    func stop() {
        process?.standardOutput = nil
        process?.terminate()
        process = nil
        stdin = nil
        buffer = Data()
        isInitialized = false
        pendingMessages = []
    }

    func didOpen(filePath: String, text: String) {
        start()
        guard process != nil else { return }
        enqueueOrSend(method: "textDocument/didOpen", params: .object([
            "textDocument": .object([
                "uri": .string(URL(fileURLWithPath: filePath).absoluteString),
                "languageId": .string(definition.id),
                "version": .number(Double(nextVersion(for: filePath))),
                "text": .string(text),
            ]),
        ]))
    }

    func didChange(filePath: String, text: String) {
        start()
        guard process != nil else { return }
        enqueueOrSend(method: "textDocument/didChange", params: .object([
            "textDocument": .object([
                "uri": .string(URL(fileURLWithPath: filePath).absoluteString),
                "version": .number(Double(nextVersion(for: filePath))),
            ]),
            "contentChanges": .array([
                .object(["text": .string(text)]),
            ]),
        ]))
    }

    func didSave(filePath: String, text: String) {
        guard process != nil else { return }
        enqueueOrSend(method: "textDocument/didSave", params: .object([
            "textDocument": .object(["uri": .string(URL(fileURLWithPath: filePath).absoluteString)]),
            "text": .string(text),
        ]))
    }

    private func initialize() {
        requestID += 1
        send(id: requestID, method: "initialize", params: .object([
            "processId": .number(Double(ProcessInfo.processInfo.processIdentifier)),
            "rootUri": .string(URL(fileURLWithPath: projectPath).absoluteString),
            "capabilities": .object([
                "textDocument": .object([
                    "publishDiagnostics": .object([:]),
                    "synchronization": .object([
                        "didOpen": .bool(true),
                        "didChange": .bool(true),
                        "didSave": .bool(true),
                    ]),
                ]),
            ]),
        ]))
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        for payload in LSPMessageFramer.extractMessages(from: &buffer) {
            guard let message = try? decoder.decode(LSPMessage.self, from: payload) else { continue }
            handle(message)
        }
    }

    private func handle(_ message: LSPMessage) {
        if message.id != nil, !isInitialized {
            isInitialized = true
            send(method: "initialized", params: .object([:]))
            flushPendingMessages()
        }

        guard message.method == "textDocument/publishDiagnostics",
              let params = message.params,
              let data = try? encoder.encode(params),
              let publish = try? decoder.decode(LSPPublishDiagnosticsParams.self, from: data)
        else { return }

        let diagnostics = LSPDiagnosticMapper.editorDiagnostics(
            params: publish,
            projectPath: projectPath,
            fallbackSource: definition.lsp?.serverID
        )
        if let filePath = diagnostics.first?.filePath ?? URL(string: publish.uri)?.path {
            DiagnosticsStore.shared.setDiagnostics(diagnostics, for: filePath)
        }
    }

    private func send(id: Int? = nil, method: String, params: JSONValue) {
        var payload: [String: JSONValue] = [
            "jsonrpc": .string("2.0"),
            "method": .string(method),
            "params": params,
        ]
        if let id { payload["id"] = .number(Double(id)) }
        guard let data = try? encoder.encode(JSONValue.object(payload)) else { return }
        stdin?.write(LSPMessageFramer.frame(data))
    }

    private func enqueueOrSend(id: Int? = nil, method: String, params: JSONValue) {
        guard isInitialized else {
            pendingMessages.append((id, method, params))
            return
        }
        send(id: id, method: method, params: params)
    }

    private func flushPendingMessages() {
        let messages = pendingMessages
        pendingMessages = []
        for message in messages {
            send(id: message.id, method: message.method, params: message.params)
        }
    }

    private func nextVersion(for filePath: String) -> Int {
        let next = (documentVersions[filePath] ?? 0) + 1
        documentVersions[filePath] = next
        return next
    }
}
