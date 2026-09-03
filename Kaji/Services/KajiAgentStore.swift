import AppKit
import Foundation

@MainActor
@Observable
final class KajiAgentStore {
    let scope: KajiAgentScope?
    private let settings = KajiAgentSettingsStore.shared
    var isReady: Bool { readiness.isReady }
    var statusMessage = "Ready"
    var readiness: KajiAgentReadiness = .checking
    var modelLabel = "Model not selected"
    var thinkingLevel = "off"
    var turns: [KajiAgentTurn] = []
    var messages: [KajiAgentMessage] { turns.flatMap(\.messages) }
    var pendingQuestion: KajiAgentQuestion?
    var pendingApproval: KajiAgentApprovalRequest?
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
    var loginStatus = "KajiCode authenticates through its own login flow."
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

    init(scope: KajiAgentScope? = nil) {
        self.scope = scope
        modelOptions = KajiAgentStore.kajiCodeModelOptions()
        modelLabel = modelOptions.first?.title ?? "Model not selected"
    }

    func configure(
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore,
        projectPathOverride: String? = nil
    ) {
        self.appState = appState
        self.projectStore = projectStore
        self.worktreeStore = worktreeStore
        refreshReadiness()
    }

    var effectivePermissionMode: KajiAgentPermissionMode {
        sessionPermissionMode ?? settings.selectedPermissionMode
    }

    func setSessionPermissionMode(_ mode: KajiAgentPermissionMode) {
        sessionPermissionMode = mode
    }

    func retryRuntimeReadiness() {
        refreshReadiness()
    }

    func refreshReadiness() {
        readiness = KajiCodeRuntimeLocator.resolve() == nil ? .missingRuntime : .ready
        statusMessage = readiness.detail
    }

    func submit(_ prompt: String, attachments: [AskAttachment]) {}

    func markUserSubmittedScrollIntent() {}

    func stop() {}

    func stopProcess() {}

    func clear() {}

    func setModel(provider: String, modelID: String) {
        if let option = modelOptions.first(where: { $0.provider == provider && $0.modelID == modelID }) {
            modelLabel = option.title
        }
    }

    func setModelRole(role: String, provider: String, modelID: String, thinkingLevel: String? = nil, temporary: Bool = false) {}

    func setThinkingLevel(_ level: String) {
        thinkingLevel = level
    }

    func login(providerID: String) {
        loginStatus = "KajiCode manages provider logins in its own CLI."
    }

    func requestAvailableModels(_ onResult: @escaping ([KajiAgentModelOption]) -> Void) {
        modelOptions = KajiAgentStore.kajiCodeModelOptions()
        onResult(modelOptions)
    }

    func requestCustomProviders(_ onResult: ((KajiAgentCustomProvidersState) -> Void)? = nil) {
        onResult?(customProvidersState)
    }

    func saveCustomProvider(_ provider: KajiAgentCustomProvider, onResult: ((Bool) -> Void)? = nil) {
        customProviderStatus = "Custom providers are managed by KajiCode."
        onResult?(false)
    }

    func deleteCustomProvider(id: String, onResult: ((Bool) -> Void)? = nil) {
        customProviderStatus = "Custom providers are managed by KajiCode."
        onResult?(false)
    }

    func previewCustomProviderModels(
        _ provider: KajiAgentCustomProvider,
        onResult: @escaping (KajiAgentCustomProviderAutoMatch?) -> Void
    ) {
        onResult(nil)
    }

    func validateCustomProviderConnection(
        _ provider: KajiAgentCustomProvider,
        onResult: @escaping (KajiAgentCustomProviderValidation?) -> Void
    ) {
        onResult(nil)
    }

    func requestModelConfig(_ onResult: @escaping (KajiAgentModelConfig) -> Void) {
        onResult(KajiAgentModelConfig(json: nil))
    }

    func requestLoginProviders(_ onResult: @escaping ([KajiAgentLoginProvider]) -> Void) {
        loginProviders = []
        onResult([])
    }

    func refreshComposerMetadata() {}

    func buildSkillPrompt(name: String, args: String, onResult: @escaping (String?) -> Void) {
        onResult(nil)
    }

    func searchHistory(query: String, onResult: @escaping ([KajiAgentHistoryMetadata]) -> Void) {
        onResult([])
    }

    func requestTools() {}

    func setActiveTools(_ names: [String]) {}

    func requestSessions(all: Bool = false, onResult: (([KajiAgentSessionOption]) -> Void)? = nil) {
        onResult?([])
    }

    func switchSession(path: String) {}

    func compact(customInstructions: String? = nil) {}

    func handoff(customInstructions: String? = nil) {}

    func executeBash(_ command: String) {}

    func answerPendingQuestion(value: String) {}

    func answerSettingsQuestion(value: String) {}

    func answerQuestion(_ question: KajiAgentQuestion, value: String) {
        clearQuestion(id: question.id)
    }

    func answerApproval(_ request: KajiAgentApprovalRequest, option: KajiAgentApprovalOption) {
        clearQuestion(id: request.id)
    }

    func cancelApproval(_ request: KajiAgentApprovalRequest) {
        clearQuestion(id: request.id)
    }

    func cancelQuestion(_ question: KajiAgentQuestion) {
        clearQuestion(id: question.id)
    }

    func cancelPendingQuestion() {}

    private func clearQuestion(id: String) {
        if pendingQuestion?.id == id {
            pendingQuestion = nil
        }
        if pendingApproval?.id == id {
            pendingApproval = nil
        }
        if settingsQuestion?.id == id {
            settingsQuestion = nil
        }
        if editorQuestion?.id == id {
            editorQuestion = nil
        }
        if loginQuestion?.id == id {
            loginQuestion = nil
        }
    }

    private static func kajiCodeModelOptions() -> [KajiAgentModelOption] {
        KajiCodeAgentModule().definition.models.map { model in
            KajiAgentModelOption(
                id: "kajicode/\(model)",
                provider: "kajicode",
                modelID: model,
                title: "kajicode / \(model)"
            )
        }
    }
}
