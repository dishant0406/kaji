import AppKit
import Foundation

@MainActor
@Observable
final class KajiAgentStore {
    let process = KajiAgentProcess()
    let scope: KajiAgentScope?
    private let settings = KajiAgentSettingsStore.shared
    var isReady = false
    var isRunning = false
    var statusMessage = "Starting Kaji Agent"
    var sessionID: String?
    var modelLabel = "Model not selected"
    var thinkingLevel = "off"
    var turns: [KajiAgentTurn] = []
    var messages: [KajiAgentMessage] { turns.flatMap(\.messages) }
    var pendingQuestion: KajiAgentQuestion?
    var settingsQuestion: KajiAgentQuestion?
    var editorQuestion: KajiAgentQuestion?
    var loginQuestion: KajiAgentQuestion?
    var loginURL: String?
    var loginInstructions: String?
    var loginCode: String?
    var loginProviders: [KajiAgentLoginProvider] = []
    var modelOptions: [KajiAgentModelOption] = []
    var modelRoles: [KajiAgentModelRoleAssignment] = []
    var cycleOrder: [String] = []
    var slashCommands: [KajiAgentSlashCommand] = []
    var skills: [KajiAgentSkillMetadata] = []
    var recentHistory: [KajiAgentHistoryMetadata] = []
    var toolOptions: [KajiAgentToolOption] = []
    var sessionOptions: [KajiAgentSessionOption] = []
    var loginStatus = "Choose a provider to connect."
    var isLoginInProgress = false
    var sessionPermissionMode: KajiAgentPermissionMode?
    var widgetLines: [String] = []
    var statusMessages: [String: String] = [:]
    var widgets: [KajiAgentWidget] = []
    var todoPhases: [KajiAgentTodoPhase] = []
    var queuedMessageCount = 0
    var tailVersion = 0
    weak var appState: AppState?
    weak var projectStore: ProjectStore?
    weak var worktreeStore: WorktreeStore?

    private var pendingResponses: [String: (KajiAgentRPCFrame) -> Void] = [:]
    private var projectPath: String?
    private var hasRequestedState = false
    private var hasConfiguredHostTools = false
    private var visibleDecodeErrors = 0
    private var activeTurnID: KajiAgentTurn.ID?

    init(scope: KajiAgentScope? = nil) {
        self.scope = scope
        process.onMessage = { [weak self] frame in self?.handle(frame) }
        process.onError = { [weak self] error in self?.handleRuntimeError(error) }
    }

    var readiness: KajiAgentReadiness {
        guard KajiAgentRuntimeLocator.bunExecutablePath() != nil else { return .missingBun }
        guard KajiAgentRuntimeLocator.sourceLaunch(projectPath: projectPath) != nil || KajiAgentRuntimeLocator.bundledScriptURL() != nil else {
            return .missingRuntime
        }
        return .ready
    }

    func configure(appState: AppState, projectStore: ProjectStore, worktreeStore: WorktreeStore, projectPathOverride: String? = nil) {
        self.appState = appState
        self.projectStore = projectStore
        self.worktreeStore = worktreeStore
        projectPath = scope?.projectPath ?? projectPathOverride ?? activeWorktreePath(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        process.projectPath = projectPath
        process.sessionDirectory = scope.map(KajiAgentSessionDirectory.path(for:))
        process.approvalMode = sessionPermissionMode?.rawValue ?? settings.selectedPermissionMode.rawValue
        send(KajiAgentRPCFrame(type: "get_state")) { [weak self] frame in
            self?.applyState(frame.data)
        }
    }

    var effectivePermissionMode: KajiAgentPermissionMode {
        sessionPermissionMode ?? settings.selectedPermissionMode
    }

    func setSessionPermissionMode(_ mode: KajiAgentPermissionMode) {
        sessionPermissionMode = mode
        process.approvalMode = mode.rawValue
        send(KajiAgentRPCFrame(type: "set_approval_mode", data: .object(["mode": .string(mode.rawValue)]))) { [weak self] frame in
            if frame.success == true {
                self?.appendSystem(title: "Permissions", detail: "\(mode.title) for this chat", kind: .event)
            } else if let error = frame.error {
                self?.appendSystem(title: "Permissions failed", detail: error, kind: .error)
            }
        }
    }

    func submit(_ prompt: String, attachments: [AskAttachment]) {
        let content = KajiAgentAttachmentFormatter.prompt(prompt, attachments: attachments)
        guard pendingQuestion == nil else {
            answerPendingQuestion(value: content)
            return
        }
        send(KajiAgentRPCFrame(type: "prompt", message: content))
    }

    func stop() {
        send(KajiAgentRPCFrame(type: "abort"))
        isRunning = false
    }

    func stopProcess() {
        process.stop()
    }

    func clear() {
        turns = []
        pendingQuestion = nil
        send(KajiAgentRPCFrame(type: "new_session")) { [weak self] frame in
            self?.applyState(frame.data)
        }
    }

    func setModel(provider: String, modelID: String) {
        send(KajiAgentRPCFrame(type: "set_model", provider: provider, modelId: modelID)) { [weak self] frame in
            self?.applySelectedModel(frame.data)
            self?.requestModelConfig { _ in }
        }
    }

    func setModelRole(role: String, provider: String, modelID: String, thinkingLevel: String? = nil, temporary: Bool = false) {
        send(KajiAgentRPCFrame(type: "set_model_role", data: .object([
            "role": .string(role),
            "provider": .string(provider),
            "modelId": .string(modelID),
            "thinkingLevel": thinkingLevel.map(KajiAgentJSONValue.string) ?? .null,
            "temporary": .bool(temporary),
        ]))) { [weak self] frame in
            if role == "default" || temporary { self?.applySelectedModel(frame.data?.objectValue?["model"]) }
            self?.requestModelConfig { _ in }
        }
    }

    func setThinkingLevel(_ level: String) {
        send(KajiAgentRPCFrame(type: "set_thinking_level", level: level))
        thinkingLevel = level
    }

    func login(providerID: String) {
        isLoginInProgress = true
        loginStatus = "Connecting \(providerID)..."
        send(KajiAgentRPCFrame(type: "login", providerId: providerID))
    }

    func requestAvailableModels(_ onResult: @escaping ([KajiAgentModelOption]) -> Void) {
        send(KajiAgentRPCFrame(type: "get_available_models")) { frame in
            let options = KajiAgentModelOption.options(from: frame.data)
            self.modelOptions = options
            onResult(options)
        }
    }

    func requestModelConfig(_ onResult: @escaping (KajiAgentModelConfig) -> Void) {
        send(KajiAgentRPCFrame(type: "get_model_config")) { [weak self] frame in
            let config = KajiAgentModelConfig(json: frame.data)
            self?.modelRoles = config.roles
            self?.cycleOrder = config.cycleOrder
            self?.modelOptions = config.models
            onResult(config)
        }
    }

    func requestLoginProviders(_ onResult: @escaping ([KajiAgentLoginProvider]) -> Void) {
        send(KajiAgentRPCFrame(type: "get_login_providers")) { frame in
            guard case let .object(data)? = frame.data,
                  case let .array(values)? = data["providers"]
            else {
                self.loginProviders = []
                onResult([])
                return
            }
            let providers = values.compactMap(KajiAgentLoginProvider.init(json:))
            self.loginProviders = providers
            onResult(providers)
        }
    }

    func refreshComposerMetadata() {
        send(KajiAgentRPCFrame(type: "get_slash_commands")) { [weak self] frame in
            guard let self else { return }
            let commands = frame.data?.objectValue?["commands"]?.arrayValue?.compactMap(KajiAgentSlashCommand.init(json:)) ?? []
            slashCommands = commands
        }
        send(KajiAgentRPCFrame(type: "get_skills")) { [weak self] frame in
            guard let self else { return }
            skills = frame.data?.objectValue?["skills"]?.arrayValue?.compactMap(KajiAgentSkillMetadata.init(json:)) ?? []
        }
        send(KajiAgentRPCFrame(type: "get_history_recent", limit: 30)) { [weak self] frame in
            guard let self else { return }
            recentHistory = frame.data?.objectValue?["entries"]?.arrayValue?.compactMap(KajiAgentHistoryMetadata.init(json:)) ?? []
        }
    }

    func buildSkillPrompt(name: String, args: String, onResult: @escaping (String?) -> Void) {
        send(KajiAgentRPCFrame(type: "build_skill_prompt", data: .object(["args": .string(args)]), name: name)) { frame in
            onResult(frame.data?.objectValue?["message"]?.stringValue)
        }
    }

    func searchHistory(query: String, onResult: @escaping ([KajiAgentHistoryMetadata]) -> Void) {
        send(KajiAgentRPCFrame(type: "search_history", query: query, limit: 20)) { frame in
            onResult(frame.data?.objectValue?["entries"]?.arrayValue?.compactMap(KajiAgentHistoryMetadata.init(json:)) ?? [])
        }
    }

    func requestTools() {
        send(KajiAgentRPCFrame(type: "get_tools")) { [weak self] frame in
            guard let self else { return }
            toolOptions = frame.data?.objectValue?["tools"]?.arrayValue?.compactMap(KajiAgentToolOption.init(json:)) ?? []
        }
    }

    func setActiveTools(_ names: [String]) {
        send(KajiAgentRPCFrame(type: "set_active_tools", data: .object(["toolNames": .array(names.map(KajiAgentJSONValue.string))]))) { [weak self] _ in
            self?.requestTools()
        }
    }

    func requestSessions(all: Bool = false, onResult: (([KajiAgentSessionOption]) -> Void)? = nil) {
        send(KajiAgentRPCFrame(type: "list_sessions", data: .object(["all": .bool(all), "limit": .number(60)]))) { [weak self] frame in
            guard let self else { return }
            let options = frame.data?.objectValue?["sessions"]?.arrayValue?.compactMap(KajiAgentSessionOption.init(json:)) ?? []
            sessionOptions = options
            onResult?(options)
        }
    }

    func switchSession(path: String) {
        send(KajiAgentRPCFrame(type: "switch_session", data: .object(["sessionPath": .string(path)]))) { [weak self] frame in
            guard let self else { return }
            if frame.success == true {
                turns = []
                send(KajiAgentRPCFrame(type: "get_messages")) { [weak self] frame in
                    self?.restoreMessages(frame.data)
                }
                send(KajiAgentRPCFrame(type: "get_state")) { [weak self] frame in self?.applyState(frame.data) }
            }
        }
    }

    func compact(customInstructions: String? = nil) {
        let data: KajiAgentJSONValue? = customInstructions.map { .object(["customInstructions": .string($0)]) }
        send(KajiAgentRPCFrame(type: "compact", data: data))
    }

    func handoff(customInstructions: String? = nil) {
        let data: KajiAgentJSONValue? = customInstructions.map { .object(["customInstructions": .string($0)]) }
        send(KajiAgentRPCFrame(type: "handoff", data: data)) { [weak self] frame in
            if let path = frame.data?.objectValue?["savedPath"]?.stringValue {
                self?.appendSystem(title: "Handoff", detail: path, kind: .event)
            }
        }
    }

    func executeBash(_ command: String) {
        send(KajiAgentRPCFrame(type: "bash", data: .object(["command": .string(command)]))) { [weak self] frame in
            self?.appendSystem(title: "Bash", detail: frame.data?.prettyDescription ?? frame.error ?? "", kind: frame.success == false ? .error : .event)
        }
    }

    func answerPendingQuestion(value: String) {
        guard let question = pendingQuestion else { return }
        clearQuestion(id: question.id)
        send(KajiAgentRPCFrame(id: question.id, type: "extension_ui_response", value: value))
    }

    func answerSettingsQuestion(value: String) {
        guard let question = settingsQuestion else { return }
        clearQuestion(id: question.id)
        send(KajiAgentRPCFrame(id: question.id, type: "extension_ui_response", value: value))
    }

    func answerQuestion(_ question: KajiAgentQuestion, value: String) {
        clearQuestion(id: question.id)
        if question.method == "confirm" {
            send(KajiAgentRPCFrame(id: question.id, type: "extension_ui_response", confirmed: value == "Confirm"))
        } else {
            send(KajiAgentRPCFrame(id: question.id, type: "extension_ui_response", value: value))
        }
    }

    func cancelQuestion(_ question: KajiAgentQuestion) {
        clearQuestion(id: question.id)
        send(KajiAgentRPCFrame(id: question.id, type: "extension_ui_response", cancelled: true))
    }

    func cancelPendingQuestion() {
        guard let question = pendingQuestion else { return }
        clearQuestion(id: question.id)
        send(KajiAgentRPCFrame(id: question.id, type: "extension_ui_response", cancelled: true))
    }

    private func send(_ frame: KajiAgentRPCFrame, onResponse: ((KajiAgentRPCFrame) -> Void)? = nil) {
        var frame = frame
        if frame.id == nil {
            frame.id = UUID().uuidString
        }
        if let id = frame.id, let onResponse {
            pendingResponses[id] = onResponse
        }
        process.send(frame)
    }

    private func handle(_ frame: KajiAgentRPCFrame) {
        KajiAgentEventLog.record("store_handle", fields: [
            "type": .string(frame.type),
            "command": .string(frame.command ?? ""),
            "eventType": .string(frame.event?.type ?? ""),
        ])
        switch frame.type {
        case "ready":
            visibleDecodeErrors = 0
            isReady = true
            statusMessage = "Ready"
            configureHostToolsIfNeeded()
            refreshComposerMetadata()
            requestModelConfig { _ in }
            requestInitialStateIfNeeded()
        case "response":
            if let id = frame.id, let handler = pendingResponses.removeValue(forKey: id) {
                handler(frame)
            }
            if frame.command == "prompt", frame.success == false, let error = frame.error {
                appendSystem(title: "Prompt failed", detail: error, kind: .error)
            }
            if frame.command == "get_state" {
                applyState(frame.data)
            }
            if frame.command == "login", frame.success == true, frame.data?.objectValue?["pending"] == nil {
                isLoginInProgress = false
                loginQuestion = nil
                clearLoginDisplayState()
                loginStatus = "Provider connected."
                refreshMetadata()
                appendSystem(title: "Login", detail: "Provider connected.", kind: .event)
            }
            if frame.command == "login", frame.success == false, let error = frame.error {
                isLoginInProgress = false
                clearLoginDisplayState()
                loginStatus = error
                appendSystem(title: "Login failed", detail: error, kind: .error)
                refreshMetadata()
            }
        case "extension_ui_request":
            handleExtensionRequest(frame)
        case "host_tool_call":
            handleHostToolCall(frame)
        case "host_uri_request":
            handleHostURIRequest(frame)
        case "agent_start":
            isRunning = true
        case "agent_end":
            isRunning = false
            send(KajiAgentRPCFrame(type: "get_state")) { [weak self] frame in self?.applyState(frame.data) }
        case "message_start", "message_update", "message_end", "tool_execution_start", "tool_execution_update", "tool_execution_end", "turn_start", "turn_end":
            handleEvent(frame.event ?? KajiAgentSessionEvent(frame: frame))
        case "fatal_error":
            appendSystem(title: "Runtime failed", detail: frame.error ?? "Unknown runtime error", kind: .error)
        default:
            break
        }
    }

    private func requestInitialStateIfNeeded() {
        guard !hasRequestedState else { return }
        hasRequestedState = true
        send(KajiAgentRPCFrame(type: "get_state")) { [weak self] frame in self?.applyState(frame.data) }
    }

    private func configureHostToolsIfNeeded() {
        guard !hasConfiguredHostTools else { return }
        hasConfiguredHostTools = true
        send(KajiAgentRPCFrame(type: "set_host_tools", tools: KajiAgentHostToolRegistry.definitions))
        send(KajiAgentRPCFrame(type: "set_host_uri_schemes", schemes: KajiAgentHostToolRegistry.uriSchemes))
    }

    private func handleEvent(_ event: KajiAgentSessionEvent) {
        KajiAgentEventLog.record("store_event", fields: [
            "type": .string(event.type),
            "messageRole": .string(event.message?.role ?? ""),
            "assistantEvent": .string(event.assistantMessageEvent?.type ?? ""),
            "contentIndex": event.assistantMessageEvent?.contentIndex.map { .number(Double($0)) } ?? .null,
            "toolName": .string(event.toolName ?? ""),
            "toolCallId": .string(event.toolCallId ?? ""),
            "visibleBlockCount": .number(Double(KajiAgentTextExtractor.blocks(from: event.message?.content).count)),
            "assistantTextCharacters": .number(Double(KajiAgentTextExtractor.assistantText(from: event.message?.content).count)),
            "thinkingCharacters": .number(Double(KajiAgentTextExtractor.thinkingText(from: event.message?.content).count)),
            "turnCount": .number(Double(turns.count)),
            "activeTurn": .string(activeTurnID?.uuidString ?? ""),
        ])
        switch event.type {
        case "message_start":
            guard let message = event.message else { return }
            append(message)
        case "message_update":
            updateAssistant(event)
        case "message_end":
            guard let message = event.message else { return }
            finish(message)
        case "tool_execution_start":
            appendToolStart(event)
        case "tool_execution_update":
            updateTool(event)
        case "tool_execution_end":
            finishTool(event)
        case "notice":
            appendSystem(title: "Notice", detail: event.message?.textContent ?? "", kind: .event)
        case "auto_compaction_start":
            statusMessage = "Compacting context"
        case "auto_compaction_end":
            statusMessage = "Ready"
        default:
            break
        }
    }

    private func append(_ message: KajiAgentRPCMessage) {
        switch message.role {
        case "user":
            startTurn(user: KajiAgentMessage(kind: .user, title: "You", detail: message.textContent))
        case "assistant":
            appendAssistantMessageStart(message)
        case "toolResult":
            break
        default:
            if message.display != false {
                appendToActiveTurn(KajiAgentMessage(kind: .event, title: message.customType ?? message.role, detail: message.textContent))
            }
        }
    }

    private func updateAssistant(_ event: KajiAgentSessionEvent) {
        guard let update = event.assistantMessageEvent else { return }
        switch update.type {
        case "text_delta":
            appendAssistantDelta(update.delta ?? "", contentIndex: update.contentIndex)
        case "thinking_delta":
            appendThinkingDelta(update.delta ?? "", contentIndex: update.contentIndex)
        case "toolcall_start", "toolcall_delta":
            break
        default:
            break
        }
    }

    private func finish(_ message: KajiAgentRPCMessage) {
        guard message.role == "assistant" else { return }
        if let errorMessage = message.errorMessage, !errorMessage.isEmpty {
            appendToActiveTurn(KajiAgentMessage(kind: .error, title: "Provider error", detail: errorMessage))
            return
        }
        let text = KajiAgentTextExtractor.assistantText(from: message.content)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            finishOpenThinkingBlocks(from: message.content)
            return
        }
        if let location = responseLocation(where: { $0.kind == .assistant && !$0.isComplete }) {
            updateMessage(at: location) { message in
                message.detail = text
                message.isComplete = true
            }
        } else {
            appendResponseMessage(KajiAgentMessage(kind: .assistant, title: "Kaji", detail: text))
        }
        finishOpenThinkingBlocks(from: message.content)
    }

    private func appendAssistantMessageStart(_ message: KajiAgentRPCMessage) {
        let parts = KajiAgentTextExtractor.blocks(from: message.content)
        guard !parts.isEmpty else { return }
        for part in parts.sorted(by: { ($0.index ?? 0) < ($1.index ?? 0) }) where !part.text.isEmpty {
            switch part.kind {
            case .text, .image:
                appendResponseMessage(KajiAgentMessage(kind: .assistant, title: "Kaji", detail: part.text, contentIndex: part.index, isComplete: false))
            case .thinking:
                appendResponseMessage(KajiAgentMessage(kind: .thinking, title: "Thinking", detail: part.text, contentIndex: part.index, isComplete: false))
            }
        }
    }

    private func appendAssistantDelta(_ text: String, contentIndex: Int?) {
        guard !text.isEmpty else { return }
        bumpTail()
        KajiAgentEventLog.record("assistant_delta", fields: [
            "contentIndex": contentIndex.map { .number(Double($0)) } ?? .null,
            "characters": .number(Double(text.count)),
            "turn": .string(activeTurnID?.uuidString ?? ""),
        ])
        if let location = responseLocation(where: { $0.kind == .assistant && !$0.isComplete && $0.contentIndex == contentIndex }) {
            updateMessage(at: location) { $0.detail += text }
        } else {
            appendResponseMessage(KajiAgentMessage(kind: .assistant, title: "Kaji", detail: text, contentIndex: contentIndex, isComplete: false))
        }
    }

    private func appendThinkingDelta(_ text: String, contentIndex: Int?) {
        guard !text.isEmpty else { return }
        bumpTail()
        KajiAgentEventLog.record("thinking_delta", fields: [
            "contentIndex": contentIndex.map { .number(Double($0)) } ?? .null,
            "characters": .number(Double(text.count)),
            "turn": .string(activeTurnID?.uuidString ?? ""),
        ])
        if let location = activeTailMessageLocation(where: { $0.kind == .thinking && !$0.isComplete && $0.contentIndex == contentIndex }) {
            updateMessage(at: location) { $0.detail += text }
        } else {
            appendResponseMessage(KajiAgentMessage(kind: .thinking, title: "Thinking", detail: text, contentIndex: contentIndex, isComplete: false))
        }
    }

    private func finishOpenThinkingBlocks(from value: KajiAgentJSONValue?) {
        let thinking = KajiAgentTextExtractor.blocks(from: value).filter { $0.kind == .thinking }
        for part in thinking {
            guard let location = responseLocation(where: { $0.kind == .thinking && $0.contentIndex == part.index }) else { continue }
            updateMessage(at: location) { message in
                if !part.text.isEmpty { message.detail = part.text }
                message.isComplete = true
            }
        }
        guard let turnIndex = activeTurnIndex() else { return }
        for blockIndex in turns[turnIndex].blocks.indices {
            guard case var .message(message) = turns[turnIndex].blocks[blockIndex], message.kind == .thinking, !message.isComplete else { continue }
            message.isComplete = true
            turns[turnIndex].blocks[blockIndex] = .message(message)
        }
    }

    private func appendToolStart(_ event: KajiAgentSessionEvent) {
        let id = event.toolCallId ?? UUID().uuidString
        bumpTail()
        KajiAgentEventLog.record("tool_start", fields: [
            "toolName": .string(event.toolName ?? ""),
            "toolCallId": .string(id),
            "turn": .string(activeTurnID?.uuidString ?? ""),
            "lastBlock": .string(activeTurnIndex().flatMap { turns[$0].blocks.last?.debugName } ?? ""),
        ])
        appendToolToActiveGroup(KajiAgentMessage(kind: .tool, title: event.toolName ?? "Tool", detail: "", toolCallID: id, toolArguments: event.args?.prettyDescription, isComplete: false))
    }

    private func updateTool(_ event: KajiAgentSessionEvent) {
        guard let id = event.toolCallId, let location = toolLocation(where: { $0.toolCallID == id }) else { return }
        bumpTail()
        updateToolOutput(at: location, output: event.partialResult?.textContent, complete: false)
        updateTaskDetails(at: location, result: event.partialResult, toolName: event.toolName)
        applyTodoPhases(from: event.partialResult, toolName: event.toolName, isError: event.isError == true, source: "partial")
    }

    private func finishTool(_ event: KajiAgentSessionEvent) {
        guard let id = event.toolCallId, let location = toolLocation(where: { $0.toolCallID == id }) else { return }
        bumpTail()
        updateToolOutput(at: location, output: event.result?.textContent, complete: true)
        updateTool(at: location) { tool in
            tool.isComplete = true
            tool.isError = event.isError == true
        }
        updateTaskDetails(at: location, result: event.result, toolName: event.toolName)
        applyTodoPhases(from: event.result, toolName: event.toolName, isError: event.isError == true, source: "final")
    }

    private func updateTaskDetails(at location: KajiAgentToolLocation, result: KajiAgentToolResult?, toolName: String?) {
        guard toolName == "task", let details = KajiAgentTaskToolDetails(json: result?.details) else { return }
        updateTool(at: location) { tool in
            tool.taskDetails = details
        }
        KajiAgentEventLog.record("task_details_applied", fields: [
            "progressCount": .number(Double(details.progress.count)),
            "resultCount": .number(Double(details.results.count)),
            "asyncState": .string(details.asyncState ?? ""),
        ])
    }

    private func updateToolOutput(at location: KajiAgentToolLocation, output: String?, complete: Bool) {
        guard let output, !output.isEmpty else { return }
        let preview = KajiAgentToolOutputPreview.make(from: output, toolName: tool(at: location)?.title ?? "Tool", complete: complete)
        updateTool(at: location) { tool in
            tool.detail = preview.summary
            tool.preview = preview.preview
            tool.fullOutput = preview.fullOutput
            tool.truncatedLineCount = preview.truncatedLineCount
        }
    }

    private func applyTodoPhases(from result: KajiAgentToolResult?, toolName: String?, isError: Bool, source: String) {
        guard toolName == "todo_write" else { return }
        if isError {
            KajiAgentEventLog.record("todo_write_failed", fields: ["source": .string(source)])
            appendSystem(title: "Todo update failed", detail: result?.textContent ?? "Progress may be stale until todo_write succeeds.", kind: .error)
            return
        }
        guard let phasesValue = result?.details?.objectValue?["phases"],
              let phases = phasesValue.arrayValue?.compactMap(KajiAgentTodoPhase.init(json:)),
              !phases.isEmpty
        else {
            KajiAgentEventLog.record("todo_write_missing_phases", fields: ["source": .string(source)])
            return
        }
        todoPhases = phases
        bumpTail()
        KajiAgentEventLog.record("todo_phases_applied", fields: [
            "source": .string(source),
            "phaseCount": .number(Double(phases.count)),
            "taskCount": .number(Double(phases.flatMap(\.tasks).count)),
            "completedCount": .number(Double(phases.flatMap(\.tasks).filter { $0.status == "completed" }.count)),
            "inProgressCount": .number(Double(phases.flatMap(\.tasks).filter { $0.status == "in_progress" }.count)),
        ])
    }

    private func startTurn(user: KajiAgentMessage) {
        bumpTail()
        if let index = activeTurnIndex(), turns[index].user == nil, turns[index].blocks.isEmpty {
            turns[index].user = user
            return
        }
        let turn = KajiAgentTurn(user: user)
        turns.append(turn)
        activeTurnID = turn.id
        KajiAgentEventLog.record("turn_start", fields: [
            "turn": .string(turn.id.uuidString),
            "userPreview": .string(String(user.detail.prefix(160))),
            "turnCount": .number(Double(turns.count)),
        ])
    }

    private func appendToActiveTurn(_ message: KajiAgentMessage) {
        appendResponseMessage(message)
    }

    private func appendResponseMessage(_ message: KajiAgentMessage) {
        bumpTail()
        ensureActiveTurn()
        guard let index = activeTurnIndex() else { return }
        turns[index].blocks.append(.message(message))
    }

    private func appendToolToActiveGroup(_ tool: KajiAgentMessage) {
        bumpTail()
        ensureActiveTurn()
        guard let turnIndex = activeTurnIndex() else { return }
        if let lastIndex = turns[turnIndex].blocks.indices.last,
           case var .toolGroup(group) = turns[turnIndex].blocks[lastIndex]
        {
            group.tools.append(tool)
            turns[turnIndex].blocks[lastIndex] = .toolGroup(group)
            KajiAgentEventLog.record("tool_group_append", fields: [
                "turn": .string(turns[turnIndex].id.uuidString),
                "group": .string(group.id.uuidString),
                "toolName": .string(tool.title),
                "toolCount": .number(Double(group.tools.count)),
            ])
            return
        }
        let group = KajiAgentToolGroup(tools: [tool])
        turns[turnIndex].blocks.append(.toolGroup(group))
        KajiAgentEventLog.record("tool_group_start", fields: [
            "turn": .string(turns[turnIndex].id.uuidString),
            "group": .string(group.id.uuidString),
            "toolName": .string(tool.title),
        ])
    }

    private func ensureActiveTurn() {
        if activeTurnIndex() != nil { return }
        let turn = KajiAgentTurn(user: nil)
        turns.append(turn)
        activeTurnID = turn.id
    }

    private func activeTurnIndex() -> Int? {
        guard let activeTurnID else { return nil }
        return turns.firstIndex { $0.id == activeTurnID }
    }

    private func responseLocation(where predicate: (KajiAgentMessage) -> Bool) -> KajiAgentResponseLocation? {
        if let activeIndex = activeTurnIndex(), let blockIndex = turns[activeIndex].blocks.lastIndex(where: { block in
            if case let .message(message) = block { return predicate(message) }
            return false
        }) {
            return KajiAgentResponseLocation(turn: activeIndex, block: blockIndex)
        }
        for turnIndex in turns.indices.reversed() {
            if let blockIndex = turns[turnIndex].blocks.lastIndex(where: { block in
                if case let .message(message) = block { return predicate(message) }
                return false
            }) {
                return KajiAgentResponseLocation(turn: turnIndex, block: blockIndex)
            }
        }
        return nil
    }

    private func activeTailMessageLocation(where predicate: (KajiAgentMessage) -> Bool) -> KajiAgentResponseLocation? {
        guard let turnIndex = activeTurnIndex(), let last = turns[turnIndex].blocks.indices.last,
              case let .message(message) = turns[turnIndex].blocks[last], predicate(message)
        else { return nil }
        return KajiAgentResponseLocation(turn: turnIndex, block: last)
    }

    private func updateMessage(at location: KajiAgentResponseLocation, mutate: (inout KajiAgentMessage) -> Void) {
        guard case var .message(message) = turns[location.turn].blocks[location.block] else { return }
        mutate(&message)
        turns[location.turn].blocks[location.block] = .message(message)
    }

    private func toolLocation(where predicate: (KajiAgentMessage) -> Bool) -> KajiAgentToolLocation? {
        if let activeIndex = activeTurnIndex(), let location = toolLocation(in: activeIndex, where: predicate) { return location }
        for turnIndex in turns.indices.reversed() {
            if let location = toolLocation(in: turnIndex, where: predicate) { return location }
        }
        return nil
    }

    private func toolLocation(in turnIndex: Int, where predicate: (KajiAgentMessage) -> Bool) -> KajiAgentToolLocation? {
        for blockIndex in turns[turnIndex].blocks.indices.reversed() {
            guard case let .toolGroup(group) = turns[turnIndex].blocks[blockIndex],
                  let toolIndex = group.tools.lastIndex(where: predicate)
            else { continue }
            return KajiAgentToolLocation(turn: turnIndex, block: blockIndex, tool: toolIndex)
        }
        return nil
    }

    private func tool(at location: KajiAgentToolLocation) -> KajiAgentMessage? {
        guard case let .toolGroup(group) = turns[location.turn].blocks[location.block], group.tools.indices.contains(location.tool) else { return nil }
        return group.tools[location.tool]
    }

    private func updateTool(at location: KajiAgentToolLocation, mutate: (inout KajiAgentMessage) -> Void) {
        guard case var .toolGroup(group) = turns[location.turn].blocks[location.block], group.tools.indices.contains(location.tool) else { return }
        mutate(&group.tools[location.tool])
        turns[location.turn].blocks[location.block] = .toolGroup(group)
    }

    private func bumpTail() {
        tailVersion &+= 1
    }

    private func handleExtensionRequest(_ frame: KajiAgentRPCFrame) {
        guard let id = frame.id, let method = frame.method else { return }
        switch method {
        case "select":
            setQuestion(KajiAgentQuestion(id: id, title: frame.title ?? "Choose an option", method: method, options: frame.options ?? []))
        case "confirm":
            setQuestion(KajiAgentQuestion(id: id, title: frame.title ?? frame.message ?? "Confirm", method: method, options: ["Confirm", "Cancel"]))
        case "input", "editor":
            setQuestion(KajiAgentQuestion(
                id: id,
                title: frame.title ?? "Kaji needs input",
                method: method,
                placeholder: frame.placeholder,
                prefill: frame.prefill,
                promptStyle: frame.promptStyle ?? false,
                isSecure: frame.isSecure ?? false,
                allowEmpty: frame.allowEmpty ?? false,
                timeout: frame.timeout,
                options: []
            ))
        case "cancel":
            if let targetID = frame.targetId { clearQuestion(id: targetID) }
        case "notify":
            appendSystem(title: frame.notifyType == "error" ? "Error" : "Notice", detail: frame.message ?? "", kind: frame.notifyType == "error" ? .error : .event)
        case "open_url":
            loginURL = frame.url
            loginInstructions = frame.instructions ?? frame.url
            loginCode = extractLoginCode(from: frame.instructions)
            loginStatus = frame.instructions ?? "Open browser to continue."
            KajiAgentEventLog.record("login_open_url", fields: [
                "url": .string(frame.url ?? ""),
                "instructions": .string(frame.instructions ?? ""),
                "code": .string(loginCode ?? ""),
            ])
            if let urlString = frame.url, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
            appendSystem(title: "Login", detail: frame.instructions ?? frame.url ?? "Opened browser", kind: .event)
        case "setWidget":
            setWidget(key: frame.widgetKey ?? "default", lines: frame.widgetLines, placement: frame.widgetPlacement)
        case "setStatus":
            setStatus(key: frame.statusKey ?? "default", text: frame.statusText)
        case "set_editor_text":
            editorQuestion = KajiAgentQuestion(id: id, title: "Runtime updated editor text", method: method, prefill: frame.text, options: [])
        case "setTitle":
            if let title = frame.title { statusMessage = title }
        default:
            break
        }
    }

    private func handleHostToolCall(_ frame: KajiAgentRPCFrame) {
        guard let id = frame.id else { return }
        Task { @MainActor in
            let result = await KajiAgentHostToolRegistry.execute(frame, appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
            send(KajiAgentRPCFrame(id: id, type: "host_tool_result", result: result, isError: result.isError))
        }
    }

    private func handleHostURIRequest(_ frame: KajiAgentRPCFrame) {
        guard let id = frame.id else { return }
        let result = KajiAgentHostToolRegistry.resolveURI(frame, appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        send(result.response(id: id))
    }

    private func appendSystem(title: String, detail: String, kind: KajiAgentMessageKind) {
        guard !detail.isEmpty else { return }
        appendToActiveTurn(KajiAgentMessage(kind: kind, title: title, detail: detail))
    }

    private func handleRuntimeError(_ error: String) {
        if error.hasPrefix("Failed to decode runtime event") {
            visibleDecodeErrors += 1
            guard visibleDecodeErrors <= 3 else { return }
        }
        appendSystem(title: "Runtime", detail: error, kind: .error)
    }

    private func applyState(_ value: KajiAgentJSONValue?) {
        guard case let .object(data)? = value else { return }
        sessionID = data["sessionId"]?.stringValue ?? data["sessionID"]?.stringValue ?? sessionID
        thinkingLevel = data["thinkingLevel"]?.stringValue ?? thinkingLevel
        queuedMessageCount = data["queuedMessageCount"]?.numberAsInt ?? queuedMessageCount
        todoPhases = data["todoPhases"]?.arrayValue?.compactMap(KajiAgentTodoPhase.init(json:)) ?? todoPhases
        if let model = data["model"]?.objectValue {
            let provider = model["provider"]?.stringValue ?? "provider"
            let id = model["id"]?.stringValue ?? "model"
            modelLabel = "\(provider) / \(id)"
        }
        if case let .bool(streaming)? = data["isStreaming"] {
            isRunning = streaming
        }
    }

    private func applySelectedModel(_ value: KajiAgentJSONValue?) {
        guard let model = value?.objectValue else { return }
        let provider = model["provider"]?.stringValue ?? "provider"
        let id = model["id"]?.stringValue ?? "model"
        modelLabel = "\(provider) / \(id)"
    }

    private func restoreMessages(_ value: KajiAgentJSONValue?) {
        guard let values = value?.objectValue?["messages"]?.arrayValue else { return }
        turns = []
        activeTurnID = nil
        for value in values {
            guard let object = value.objectValue,
                  let role = object["role"]?.stringValue
            else { continue }
            let text = KajiAgentTextExtractor.text(from: object["content"])
            switch role {
            case "user":
                startTurn(user: KajiAgentMessage(kind: .user, title: "You", detail: text))
            case "assistant":
                restoreAssistantContent(object["content"])
                if let error = object["errorMessage"]?.stringValue, !error.isEmpty {
                    appendToActiveTurn(KajiAgentMessage(kind: .error, title: "Provider error", detail: error))
                }
            case "toolResult":
                restoreToolResult(object)
            default:
                guard object["display"]?.boolValue != false else { continue }
                appendToActiveTurn(KajiAgentMessage(kind: .event, title: object["customType"]?.stringValue ?? role, detail: text))
            }
        }
    }

    private func restoreAssistantContent(_ content: KajiAgentJSONValue?) {
        guard let values = content?.arrayValue else {
            let text = KajiAgentTextExtractor.assistantText(from: content)
            if !text.isEmpty { appendToActiveTurn(KajiAgentMessage(kind: .assistant, title: "Kaji", detail: text)) }
            return
        }
        for value in values {
            guard let object = value.objectValue, let type = object["type"]?.stringValue else { continue }
            switch type {
            case "thinking":
                let text = object["thinking"]?.stringValue ?? ""
                if !text.isEmpty { appendToActiveTurn(KajiAgentMessage(kind: .thinking, title: "Thinking", detail: text)) }
            case "text":
                let text = object["text"]?.stringValue ?? ""
                if !text.isEmpty { appendToActiveTurn(KajiAgentMessage(kind: .assistant, title: "Kaji", detail: text)) }
            case "image":
                let label = object["mimeType"]?.stringValue ?? object["mime_type"]?.stringValue ?? "image"
                appendToActiveTurn(KajiAgentMessage(kind: .assistant, title: "Kaji", detail: "[Image: \(label)]"))
            case "toolCall":
                restoreToolCall(object)
            default:
                break
            }
        }
    }

    private func restoreToolCall(_ object: [String: KajiAgentJSONValue]) {
        let id = object["id"]?.stringValue ?? UUID().uuidString
        let name = object["name"]?.stringValue ?? "Tool"
        appendToolToActiveGroup(KajiAgentMessage(
            kind: .tool,
            title: name,
            detail: "Pending result",
            toolCallID: id,
            toolArguments: object["arguments"]?.prettyDescription,
            isComplete: false
        ))
    }

    private func restoreToolResult(_ object: [String: KajiAgentJSONValue]) {
        let id = object["toolCallId"]?.stringValue ?? UUID().uuidString
        let name = object["toolName"]?.stringValue ?? "Tool"
        if toolLocation(where: { $0.toolCallID == id }) == nil {
            appendToolToActiveGroup(KajiAgentMessage(kind: .tool, title: name, detail: "", toolCallID: id, isComplete: false))
        }
        guard let location = toolLocation(where: { $0.toolCallID == id }) else { return }
        let output = KajiAgentTextExtractor.text(from: object["content"])
        updateToolOutput(at: location, output: output, complete: true)
        updateTool(at: location) { tool in
            tool.isComplete = true
            tool.isError = object["isError"]?.boolValue == true
        }
        if name == "todo_write" {
            applyTodoPhases(
                from: KajiAgentToolResult(content: [], details: object["details"], isError: object["isError"]?.boolValue),
                toolName: name,
                isError: object["isError"]?.boolValue == true,
                source: "restore"
            )
        }
    }

    private func refreshMetadata() {
        requestAvailableModels { _ in }
        requestModelConfig { _ in }
        requestLoginProviders { _ in }
    }

    private func setQuestion(_ question: KajiAgentQuestion) {
        if isLoginInProgress {
            loginQuestion = question
            settingsQuestion = question
            return
        }
        pendingQuestion = question
        settingsQuestion = question
        if question.method == "editor" { editorQuestion = question }
    }

    private func clearQuestion(id: String) {
        if pendingQuestion?.id == id { pendingQuestion = nil }
        if settingsQuestion?.id == id { settingsQuestion = nil }
        if editorQuestion?.id == id { editorQuestion = nil }
        if loginQuestion?.id == id { loginQuestion = nil }
    }

    private func clearLoginDisplayState() {
        loginURL = nil
        loginInstructions = nil
        loginCode = nil
    }

    private func extractLoginCode(from instructions: String?) -> String? {
        guard let instructions else { return nil }
        let pattern = #"(?i)(?:enter\s+code|code)[:\s]+([A-Z0-9\-]{4,})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: instructions, range: NSRange(instructions.startIndex..., in: instructions)),
              let range = Range(match.range(at: 1), in: instructions)
        else { return nil }
        return String(instructions[range])
    }

    private func setStatus(key: String, text: String?) {
        if let text, !text.isEmpty {
            statusMessages[key] = text
            statusMessage = text
        } else {
            statusMessages.removeValue(forKey: key)
            statusMessage = statusMessages.values.first ?? "Ready"
        }
    }

    private func setWidget(key: String, lines: [String]?, placement: String?) {
        widgets.removeAll { $0.key == key }
        if let lines, !lines.isEmpty {
            widgets.append(KajiAgentWidget(key: key, placement: placement ?? "belowEditor", lines: lines))
        }
        widgetLines = widgets.flatMap(\.lines)
    }

    private func activeWorktreePath(appState: AppState, projectStore: ProjectStore, worktreeStore: WorktreeStore) -> String? {
        guard let projectID = appState.activeProjectID,
              let project = projectStore.projects.first(where: { $0.id == projectID })
        else { return nil }
        worktreeStore.ensurePrimary(for: project)
        guard let key = appState.activeWorktreeKey(for: project.id) else { return project.path }
        return worktreeStore.worktree(projectID: project.id, worktreeID: key.worktreeID)?.path ?? project.path
    }
}

struct KajiAgentMessage: Identifiable, Hashable {
    let id = UUID()
    var kind: KajiAgentMessageKind
    var title: String
    var detail: String
    var contentIndex: Int?
    var toolCallID: String?
    var toolArguments: String?
    var preview: String?
    var fullOutput: String?
    var taskDetails: KajiAgentTaskToolDetails?
    var truncatedLineCount = 0
    var isComplete = true
    var isError = false
    var isExpanded = false
}

struct KajiAgentTurn: Identifiable, Hashable {
    let id = UUID()
    var user: KajiAgentMessage?
    var blocks: [KajiAgentResponseBlock] = []
    var isActive = true
    var createdAt = Date()

    var messages: [KajiAgentMessage] {
        let response = blocks.flatMap(\.messages)
        if let user { return [user] + response }
        return response
    }

    var toolGroups: [KajiAgentToolGroup] {
        blocks.compactMap {
            if case let .toolGroup(group) = $0 { return group }
            return nil
        }
    }
}

enum KajiAgentResponseBlock: Identifiable, Hashable {
    case message(KajiAgentMessage)
    case toolGroup(KajiAgentToolGroup)

    var id: UUID {
        switch self {
        case let .message(message): message.id
        case let .toolGroup(group): group.id
        }
    }

    var messages: [KajiAgentMessage] {
        switch self {
        case let .message(message): [message]
        case let .toolGroup(group): group.tools
        }
    }

    var debugName: String {
        switch self {
        case let .message(message):
            return "message:\(message.kind)"
        case let .toolGroup(group):
            return "toolGroup:\(group.tools.count)"
        }
    }
}

struct KajiAgentToolGroup: Identifiable, Hashable {
    let id = UUID()
    var tools: [KajiAgentMessage] = []
    var isExpanded = false

    var title: String {
        if let running = tools.last(where: { !$0.isComplete }) {
            return running.title
        }
        guard tools.count != 1 else { return tools[0].title }
        return "Tools called (\(tools.count))"
    }

    var hasError: Bool { tools.contains { $0.isError } }
    var isComplete: Bool { tools.allSatisfy(\.isComplete) }
}

private struct KajiAgentResponseLocation {
    let turn: Int
    let block: Int
}

private struct KajiAgentToolLocation {
    let turn: Int
    let block: Int
    let tool: Int
}

enum KajiAgentMessageKind: Hashable {
    case user
    case assistant
    case thinking
    case tool
    case event
    case error
}

struct KajiAgentQuestion: Hashable {
    let id: String
    let title: String
    var method: String = "input"
    var placeholder: String? = nil
    var prefill: String? = nil
    var promptStyle = false
    var isSecure = false
    var allowEmpty = false
    var timeout: Double? = nil
    let options: [String]
}

struct KajiAgentWidget: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let placement: String
    let lines: [String]
}

struct KajiAgentTodoPhase: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let tasks: [KajiAgentTodoItem]

    init?(json: KajiAgentJSONValue) {
        guard let object = json.objectValue,
              let name = object["name"]?.stringValue
        else { return nil }
        self.name = name
        self.tasks = object["tasks"]?.arrayValue?.compactMap(KajiAgentTodoItem.init(json:)) ?? []
    }
}

struct KajiAgentTodoItem: Identifiable, Hashable {
    var id: String { content }
    let content: String
    let status: String
    let notes: [String]

    init?(json: KajiAgentJSONValue) {
        guard let object = json.objectValue,
              let content = object["content"]?.stringValue,
              let status = object["status"]?.stringValue
        else { return nil }
        self.content = content
        self.status = status
        self.notes = object["notes"]?.arrayValue?.compactMap(\.stringValue) ?? []
    }
}

struct KajiAgentModelOption: Identifiable, Hashable {
    let id: String
    let provider: String
    let modelID: String
    let title: String

    static func options(from value: KajiAgentJSONValue?) -> [KajiAgentModelOption] {
        guard case let .object(data)? = value,
              case let .array(models)? = data["models"]
        else { return [] }
        return models.compactMap { value in
            guard let object = value.objectValue,
                  let provider = object["provider"]?.stringValue,
                  let id = object["id"]?.stringValue
            else { return nil }
            return KajiAgentModelOption(id: "\(provider)/\(id)", provider: provider, modelID: id, title: "\(provider) / \(id)")
        }
    }
}

private extension KajiAgentRPCMessage {
    var textContent: String {
        KajiAgentTextExtractor.text(from: content)
    }
}

private extension KajiAgentToolResult {
    var textContent: String {
        content.compactMap(\.text).joined(separator: "\n")
    }
}

private extension KajiAgentJSONValue {
    var numberAsInt: Int? {
        if case let .number(value) = self { return Int(value) }
        return nil
    }

    var prettyDescription: String {
        switch self {
        case let .string(value): value
        case let .number(value): String(value)
        case let .bool(value): String(value)
        case let .array(values): values.map(\.prettyDescription).joined(separator: "\n")
        case let .object(values): values.map { "\($0.key): \($0.value.prettyDescription)" }.sorted().joined(separator: "\n")
        case .null: ""
        }
    }
}

private extension KajiAgentLoginProvider {
    init?(json: KajiAgentJSONValue) {
        guard let object = json.objectValue,
              let id = object["id"]?.stringValue,
              let name = object["name"]?.stringValue
        else { return nil }
        self.id = id
        self.name = name
        self.available = if case let .bool(value)? = object["available"] { value } else { false }
        self.authenticated = if case let .bool(value)? = object["authenticated"] { value } else { false }
        self.authProviderID = object["authProviderId"]?.stringValue
        self.modelProviderID = object["modelProviderId"]?.stringValue
        self.availableModelCount = object["availableModelCount"]?.numberAsInt
    }
}

private extension KajiAgentSessionEvent {
    init(frame: KajiAgentRPCFrame) {
        self.init(type: frame.type, toolCallId: frame.toolCallId, toolName: frame.toolName, args: frame.data)
    }
}
