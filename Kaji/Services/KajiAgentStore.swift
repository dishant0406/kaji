import AppKit
import Foundation

@MainActor
@Observable
final class KajiAgentStore {
    let process: KajiAgentProcess
    let scope: KajiAgentScope?
    private let settings = KajiAgentSettingsStore.shared
    var isReady = false
    var isRunning = false
    var statusMessage = "Starting Kaji Agent"
    var readiness: KajiAgentReadiness = .checking
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
    var customProvidersState = KajiAgentCustomProvidersState(json: nil)
    var customProviderStatus = ""
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
    var autoScrollVersion = 0
    var forceScrollVersion = 0
    var userSubmittedScrollVersion = 0
    var isRestoringTranscript = false
    weak var appState: AppState?
    weak var projectStore: ProjectStore?
    weak var worktreeStore: WorktreeStore?

    private let pendingRPC: KajiAgentPendingRPC
    private let runtimeReadiness = KajiAgentRuntimeReadinessController()
    private var projectPath: String?
    private var hasRequestedState = false
    private var hasConfiguredHostTools = false
    private var runtimeErrorGate = KajiAgentRuntimeErrorGate()
    private var activeTurnID: KajiAgentTurn.ID?
    private var awaitingAbortStateReconciliation = false
    private var timelineUpdateCoalescer = KajiAgentTimelineUpdateCoalescer()
    private var timelineFlushTask: Task<Void, Never>?
    private var restoredTranscriptSessionKey: String?
    private var restoringTranscriptSessionKey: String?

    init(scope: KajiAgentScope? = nil) {
        let process = KajiAgentProcess()
        self.process = process
        pendingRPC = KajiAgentPendingRPC(process: process)
        self.scope = scope
        process.onMessage = { [weak self] frame in self?.handle(frame) }
        process.onError = { [weak self] error in self?.handleRuntimeError(error) }
    }

    func configure(appState: AppState, projectStore: ProjectStore, worktreeStore: WorktreeStore, projectPathOverride: String? = nil) {
        self.appState = appState
        self.projectStore = projectStore
        self.worktreeStore = worktreeStore
        projectPath = scope?.projectPath ?? projectPathOverride ?? activeWorktreePath(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
        process.projectPath = projectPath
        process.sessionDirectory = scope.map(KajiAgentSessionDirectory.path(for:))
        process.approvalMode = sessionPermissionMode?.rawValue ?? settings.selectedPermissionMode.rawValue
        refreshRuntimeReadiness(force: true)
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
        refreshRuntimeReadiness(force: true)
        send(KajiAgentRPCFrame(type: "set_approval_mode", data: .object(["mode": .string(mode.rawValue)]))) { [weak self] frame in
            if frame.success == true {
                self?.appendSystem(title: "Permissions", detail: "\(mode.title) for this chat", kind: .event)
            } else if let error = frame.error {
                self?.appendSystem(title: "Permissions failed", detail: error, kind: .error)
            }
        }
    }

    func retryRuntimeReadiness() {
        guard !readiness.isReady else { return }
        KajiAgentRuntimeLocator.clearCache()
        refreshRuntimeReadiness(force: true)
    }

    func submit(_ prompt: String, attachments: [AskAttachment]) {
        let content = KajiAgentAttachmentFormatter.prompt(prompt, attachments: attachments)
        guard pendingQuestion == nil else {
            answerPendingQuestion(value: content)
            return
        }
        send(KajiAgentRPCFrame(type: "prompt", message: content))
    }

    func markUserSubmittedScrollIntent() {
        userSubmittedScrollVersion &+= 1
    }

    func stop() {
        flushPendingTimelineUpdates()
        awaitingAbortStateReconciliation = true
        KajiAgentTimeline.reconcileAbortedWork(turns: &turns, todoPhases: &todoPhases, tailVersion: &tailVersion)
        send(KajiAgentRPCFrame(type: "abort"))
        isRunning = false
    }

    func stopProcess() {
        awaitingAbortStateReconciliation = false
        cancelPendingTimelineUpdates()
        process.stop()
    }

    func clear() {
        awaitingAbortStateReconciliation = false
        cancelPendingTimelineUpdates()
        turns = []
        activeTurnID = nil
        isRestoringTranscript = false
        restoredTranscriptSessionKey = nil
        restoringTranscriptSessionKey = nil
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

    func requestCustomProviders(_ onResult: ((KajiAgentCustomProvidersState) -> Void)? = nil) {
        send(KajiAgentRPCFrame(type: "get_custom_providers")) { [weak self] frame in
            guard let self else { return }
            if frame.success == false {
                customProviderStatus = frame.error ?? "Unable to load custom providers."
                onResult?(customProvidersState)
                return
            }
            let state = KajiAgentCustomProvidersState(json: frame.data)
            customProvidersState = state
            customProviderStatus = ""
            onResult?(state)
        }
    }

    func saveCustomProvider(_ provider: KajiAgentCustomProvider, onResult: ((Bool) -> Void)? = nil) {
        send(KajiAgentRPCFrame(type: "save_custom_provider", data: provider.json)) { [weak self] frame in
            guard let self else { return }
            if frame.success == false {
                customProviderStatus = frame.error ?? "Unable to save custom provider."
                onResult?(false)
                return
            }
            applyCustomProviderMutation(frame.data)
            customProviderStatus = "Custom provider saved."
            onResult?(true)
        }
    }

    func deleteCustomProvider(id: String, onResult: ((Bool) -> Void)? = nil) {
        send(KajiAgentRPCFrame(type: "delete_custom_provider", providerId: id)) { [weak self] frame in
            guard let self else { return }
            if frame.success == false {
                customProviderStatus = frame.error ?? "Unable to delete custom provider."
                onResult?(false)
                return
            }
            applyCustomProviderMutation(frame.data)
            customProviderStatus = "Custom provider deleted."
            onResult?(true)
        }
    }

    func previewCustomProviderModels(
        _ provider: KajiAgentCustomProvider,
        onResult: @escaping (KajiAgentCustomProviderAutoMatch?) -> Void
    ) {
        send(KajiAgentRPCFrame(type: "preview_custom_provider_models", data: provider.json)) { [weak self] frame in
            guard let self else { return }
            if frame.success == false {
                customProviderStatus = frame.error ?? "Unable to auto-match provider models."
                onResult(nil)
                return
            }
            let result = KajiAgentCustomProviderAutoMatch(json: frame.data)
            customProviderStatus = result.models.isEmpty ? "No matching models found." : "Auto-matched \(result.models.count) models."
            onResult(result)
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
        send(KajiAgentRPCFrame(
            type: "set_active_tools",
            data: .object(["toolNames": .array(names.map(KajiAgentJSONValue.string))])
        )) { [weak self] _ in
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
        flushPendingTimelineUpdates()
        isRestoringTranscript = true
        restoringTranscriptSessionKey = path
        send(KajiAgentRPCFrame(type: "switch_session", data: .object(["sessionPath": .string(path)]))) { [weak self] frame in
            guard let self else { return }
            guard frame.success == true else {
                isRestoringTranscript = false
                restoringTranscriptSessionKey = nil
                return
            }
            send(KajiAgentRPCFrame(type: "get_messages")) { [weak self] frame in
                self?.restoreMessages(frame.data, sessionKey: path)
            }
            send(KajiAgentRPCFrame(type: "get_state")) { [weak self] frame in self?.applyState(frame.data) }
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
            self?.appendSystem(
                title: "Bash",
                detail: frame.data?.prettyDescription ?? frame.error ?? "",
                kind: frame.success == false ? .error : .event
            )
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
        switch pendingRPC.send(frame, readiness: readiness, onResponse: onResponse) {
        case .sent:
            break
        case .queued:
            refreshRuntimeReadiness(force: false)
        case let .rejected(detail):
            appendSystem(title: "Runtime", detail: detail, kind: .error)
        }
    }

    private func refreshRuntimeReadiness(force: Bool) {
        runtimeReadiness.refresh(
            configuration: runtimeConfiguration(),
            currentReadiness: readiness,
            force: force
        ) { [weak self] in
            self?.readiness = .checking
            self?.statusMessage = "Checking Kaji Agent runtime"
        } onResolution: { [weak self] resolution in
            self?.applyRuntimeResolution(resolution)
        }
    }

    private func applyRuntimeResolution(_ resolution: KajiAgentLaunchResolution) {
        readiness = resolution.readiness
        switch resolution {
        case let .ready(launch):
            process.launch = launch
            statusMessage = isReady ? "Ready" : "Starting Kaji Agent"
            drainPendingSends()
        case .missingRuntime,
             .missingBun,
             .unsupportedBunVersion:
            process.launch = nil
            statusMessage = readiness.detail
            failPendingSends(readiness.detail)
        }
    }

    private func drainPendingSends() {
        pendingRPC.drainQueuedFrames()
    }

    private func failPendingSends(_ detail: String) {
        let frames = pendingRPC.failQueuedFrames()
        if frames.contains(where: { $0.type != "get_state" }) {
            appendSystem(title: "Runtime", detail: detail, kind: .error)
        }
    }

    private func runtimeConfiguration() -> KajiAgentRuntimeConfiguration {
        KajiAgentRuntimeConfiguration(
            projectPath: projectPath,
            sessionDirectory: process.sessionDirectory,
            approvalMode: process.approvalMode
        )
    }

    private func handle(_ frame: KajiAgentRPCFrame) {
        KajiAgentEventLog.record("store_handle", fields: [
            "type": .string(frame.type),
            "command": .string(frame.command ?? ""),
            "eventType": .string(frame.event?.type ?? ""),
        ])
        switch frame.type {
        case "ready":
            runtimeErrorGate.reset()
            isReady = true
            statusMessage = "Ready"
            configureHostToolsIfNeeded()
            refreshComposerMetadata()
            requestModelConfig { _ in }
            requestInitialStateIfNeeded()
        case "response":
            _ = pendingRPC.handleResponse(frame)
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
            awaitingAbortStateReconciliation = false
            isRunning = true
        case "agent_end":
            isRunning = false
            send(KajiAgentRPCFrame(type: "get_state")) { [weak self] frame in self?.applyState(frame.data) }
        case "message_start",
             "message_update",
             "message_end",
             "tool_execution_start",
             "tool_execution_update",
             "tool_execution_end",
             "turn_start",
             "turn_end":
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

    private func applyCustomProviderMutation(_ data: KajiAgentJSONValue?) {
        customProvidersState = KajiAgentCustomProvidersState(json: data)
        if let models = data?.objectValue?["models"] {
            modelOptions = KajiAgentModelOption.options(from: .object(["models": models]))
        }
        requestModelConfig { _ in }
    }

    private func bumpAutoScrollVersion() {
        autoScrollVersion &+= 1
    }

    private func bumpForceScrollVersion() {
        forceScrollVersion &+= 1
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
        if enqueuePendingTimelineUpdate(event) { return }
        flushPendingTimelineUpdates()
        switch event.type {
        case "message_start":
            guard let message = event.message else { return }
            append(message)
            bumpAutoScrollVersion()
        case "message_update":
            KajiAgentAssistantTimelineApplier.apply(
                update: event.assistantMessageEvent,
                turns: &turns,
                activeTurnID: &activeTurnID,
                tailVersion: &tailVersion
            )
            bumpAutoScrollVersion()
        case "message_end":
            guard let message = event.message, message.role == "assistant" else { return }
            KajiAgentAssistantTimelineApplier.finishAssistant(
                content: message.content,
                errorMessage: message.errorMessage,
                turns: &turns,
                activeTurnID: &activeTurnID,
                tailVersion: &tailVersion
            )
            bumpAutoScrollVersion()
        case "tool_execution_start":
            KajiAgentToolTimelineApplier.start(
                event: event,
                turns: &turns,
                activeTurnID: &activeTurnID,
                tailVersion: &tailVersion
            )
            bumpAutoScrollVersion()
        case "tool_execution_update":
            if let message = KajiAgentToolTimelineApplier.update(
                event: event,
                turns: &turns,
                activeTurnID: activeTurnID,
                tailVersion: &tailVersion,
                todoPhases: &todoPhases
            ) {
                appendSystem(message)
            }
            reconcileAbortStateIfNeeded()
        case "tool_execution_end":
            if let message = KajiAgentToolTimelineApplier.finish(
                event: event,
                turns: &turns,
                activeTurnID: activeTurnID,
                tailVersion: &tailVersion,
                todoPhases: &todoPhases
            ) {
                appendSystem(message)
            }
            reconcileAbortStateIfNeeded()
            bumpAutoScrollVersion()
        case "notice":
            appendSystem(title: "Notice", detail: event.message?.textContent ?? "", kind: .event)
            bumpAutoScrollVersion()
        case "auto_compaction_start":
            statusMessage = "Compacting context"
        case "auto_compaction_end":
            statusMessage = "Ready"
        default:
            break
        }
    }

    private func reconcileAbortStateIfNeeded() {
        guard awaitingAbortStateReconciliation, !isRunning else { return }
        KajiAgentTimeline.reconcileAbortedWork(turns: &turns, todoPhases: &todoPhases, tailVersion: &tailVersion)
    }

    private func enqueuePendingTimelineUpdate(_ event: KajiAgentSessionEvent) -> Bool {
        if event.type == "message_update", let update = event.assistantMessageEvent, update.isTimelineTextDelta {
            flushPendingToolUpdates()
            guard timelineUpdateCoalescer.enqueueAssistantDelta(update) else { return false }
            schedulePendingTimelineFlush()
            return true
        }
        if event.type == "tool_execution_update" {
            flushPendingAssistantDeltas()
            guard timelineUpdateCoalescer.enqueueToolUpdate(event) else { return false }
            schedulePendingTimelineFlush()
            return true
        }
        return false
    }

    private func schedulePendingTimelineFlush() {
        guard timelineFlushTask == nil else { return }
        timelineFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            self?.flushPendingTimelineUpdates()
        }
    }

    private func flushPendingTimelineUpdates() {
        timelineFlushTask?.cancel()
        timelineFlushTask = nil
        flushPendingAssistantDeltas()
        flushPendingToolUpdates()
    }

    private func flushPendingAssistantDeltas() {
        for update in timelineUpdateCoalescer.drainAssistantDeltas() {
            KajiAgentAssistantTimelineApplier.apply(
                update: update,
                turns: &turns,
                activeTurnID: &activeTurnID,
                tailVersion: &tailVersion
            )
        }
    }

    private func flushPendingToolUpdates() {
        for event in timelineUpdateCoalescer.drainToolUpdates() {
            if let message = KajiAgentToolTimelineApplier.update(
                event: event,
                turns: &turns,
                activeTurnID: activeTurnID,
                tailVersion: &tailVersion,
                todoPhases: &todoPhases
            ) {
                appendSystem(message)
            }
            reconcileAbortStateIfNeeded()
        }
    }

    private func cancelPendingTimelineUpdates() {
        timelineFlushTask?.cancel()
        timelineFlushTask = nil
        timelineUpdateCoalescer.removeAll()
    }

    private func append(_ message: KajiAgentRPCMessage) {
        switch message.role {
        case "user":
            KajiAgentTimeline.startTurn(
                user: KajiAgentMessage(kind: .user, title: "You", detail: message.textContent),
                turns: &turns,
                activeTurnID: &activeTurnID,
                tailVersion: &tailVersion
            )
        case "assistant":
            KajiAgentAssistantTimelineApplier.appendStart(
                content: message.content,
                turns: &turns,
                activeTurnID: &activeTurnID,
                tailVersion: &tailVersion
            )
        case "toolResult":
            break
        default:
            if message.display != false {
                KajiAgentTimeline.appendResponseMessage(
                    KajiAgentMessage(kind: .event, title: message.customType ?? message.role, detail: message.textContent),
                    turns: &turns,
                    activeTurnID: &activeTurnID,
                    tailVersion: &tailVersion
                )
            }
        }
    }

    private func handleExtensionRequest(_ frame: KajiAgentRPCFrame) {
        for action in KajiAgentExtensionRequestParser.actions(for: frame) {
            applyExtensionRequestAction(action)
        }
    }

    private func applyExtensionRequestAction(_ action: KajiAgentExtensionRequestAction) {
        switch action {
        case let .question(question):
            setQuestion(question)
        case let .clearQuestion(id):
            clearQuestion(id: id)
        case let .system(title, detail, kind):
            appendSystem(title: title, detail: detail, kind: kind)
        case let .loginDisplay(display):
            loginURL = display.url
            loginInstructions = display.instructions
            loginCode = display.code
            loginStatus = display.status
            KajiAgentEventLog.record("login_open_url", fields: [
                "url": .string(display.url ?? ""),
                "instructions": .string(display.instructions ?? ""),
                "code": .string(display.code ?? ""),
            ])
        case let .openURL(urlString):
            if let urlString, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        case let .widget(key, lines, placement):
            setWidget(key: key, lines: lines, placement: placement)
        case let .status(key, text):
            setStatus(key: key, text: text)
        case let .editorQuestion(question):
            editorQuestion = question
        case let .title(title):
            statusMessage = title
        }
    }

    private func handleHostToolCall(_ frame: KajiAgentRPCFrame) {
        guard let id = frame.id else { return }
        Task { @MainActor in
            let result = await KajiAgentHostToolRegistry.execute(
                frame,
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore
            )
            send(KajiAgentRPCFrame(id: id, type: "host_tool_result", result: result, isError: result.isError))
        }
    }

    private func handleHostURIRequest(_ frame: KajiAgentRPCFrame) {
        guard let id = frame.id else { return }
        let result = KajiAgentHostToolRegistry.resolveURI(
            frame,
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
        send(result.response(id: id))
    }

    private func appendSystem(title: String, detail: String, kind: KajiAgentMessageKind) {
        guard !detail.isEmpty else { return }
        appendSystem(KajiAgentMessage(kind: kind, title: title, detail: detail))
    }

    private func appendSystem(_ message: KajiAgentMessage) {
        guard !message.detail.isEmpty else { return }
        KajiAgentTimeline.appendResponseMessage(
            message,
            turns: &turns,
            activeTurnID: &activeTurnID,
            tailVersion: &tailVersion
        )
    }

    private func handleRuntimeError(_ error: String) {
        guard runtimeErrorGate.shouldShow(error) else { return }
        appendSystem(title: "Runtime", detail: error, kind: .error)
    }

    private func applyState(_ value: KajiAgentJSONValue?) {
        guard let snapshot = KajiAgentRuntimeStateSnapshot(json: value) else { return }
        sessionID = snapshot.sessionID ?? sessionID
        thinkingLevel = snapshot.thinkingLevel ?? thinkingLevel
        queuedMessageCount = snapshot.queuedMessageCount ?? queuedMessageCount
        todoPhases = snapshot.todoPhases ?? todoPhases
        modelLabel = snapshot.modelLabel ?? modelLabel
        isRunning = snapshot.isRunning ?? isRunning
        restoreTranscriptIfNeeded(snapshot)
        if awaitingAbortStateReconciliation, !isRunning {
            KajiAgentTimeline.reconcileAbortedWork(turns: &turns, todoPhases: &todoPhases, tailVersion: &tailVersion)
            awaitingAbortStateReconciliation = false
        }
    }

    private func applySelectedModel(_ value: KajiAgentJSONValue?) {
        modelLabel = KajiAgentRuntimeStateSnapshot.modelLabel(from: value) ?? modelLabel
    }

    private func restoreTranscriptIfNeeded(_ snapshot: KajiAgentRuntimeStateSnapshot) {
        guard let messageCount = snapshot.messageCount, messageCount > 0 else { return }
        guard turns.isEmpty, !isRestoringTranscript else { return }
        let sessionKey = snapshot.sessionFile ?? snapshot.sessionID ?? "current"
        guard restoredTranscriptSessionKey != sessionKey, restoringTranscriptSessionKey != sessionKey else { return }
        isRestoringTranscript = true
        restoringTranscriptSessionKey = sessionKey
        send(KajiAgentRPCFrame(type: "get_messages")) { [weak self] frame in
            self?.restoreMessages(frame.data, sessionKey: sessionKey)
        }
    }

    private func restoreMessages(_ value: KajiAgentJSONValue?, sessionKey: String? = nil) {
        defer { isRestoringTranscript = false }
        if restoringTranscriptSessionKey == sessionKey || sessionKey == nil {
            restoringTranscriptSessionKey = nil
        }
        guard let restoration = KajiAgentTranscriptRestorer.restore(from: value) else { return }
        turns = restoration.turns
        activeTurnID = restoration.activeTurnID
        restoredTranscriptSessionKey = sessionKey ?? restoredTranscriptSessionKey
        if let restoredTodoPhases = restoration.todoPhases {
            todoPhases = restoredTodoPhases
        }
        bumpForceScrollVersion()
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
