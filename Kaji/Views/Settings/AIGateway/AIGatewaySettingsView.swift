import SwiftUI

struct AIGatewaySettingsView: View {
    @State var store = AIGatewaySettingsStore.shared
    @State var runtime = AIGatewayRuntimeController.shared
    @State var installState = AIGatewayClaudeCodeRouterInstaller.state()
    @State var draft = AIGatewaySetupDraft.current(settings: AIGatewaySettingsStore.shared.settings)
    @State var message: String?
    @State var isWorking = false
    @State var showAdvanced = false
    @State var restartTask: Task<Void, Never>?

    var body: some View {
        SettingsContainer {
            AIGatewayOverviewSection(
                plan: setupPlan,
                status: runtime.status,
                endpoint: store.settings.endpointBaseURL,
                message: message,
                isWorking: isWorking,
                onPrimary: runQuickSetup,
                onStop: stop
            )
            AIGatewayQuickSetupSection(
                draft: $draft,
                hasSavedKey: selectedProviderKeySaved,
                validationMessage: validationMessage
            )
            AIGatewayClientSetupSection(
                draft: $draft,
                onApplyClaude: applyClaudeFromDraft,
                onApplyCodex: applyCodexFromDraft
            )
            AIGatewayAdvancedSection(isExpanded: $showAdvanced) {
                advancedSections
            }
        }
        .onAppear(perform: refresh)
    }

    private var advancedSections: some View {
        Group {
            AIGatewayRuntimeSection(
                settings: store.settings,
                status: runtime.status,
                installState: installState,
                message: message,
                isWorking: isWorking,
                onInstall: install,
                onUninstall: uninstall,
                onEnabled: setEnabled,
                onAutoStart: setAutoStart,
                onBind: setBind,
                onPort: setPort,
                onStart: start,
                onStop: stop,
                onRestart: restart,
                onRotateToken: rotateToken
            )
            AIGatewayProvidersSection(
                providers: store.settings.providers,
                keyStatus: { store.providerKeyStatus(providerID: $0) },
                onUpdate: updateProvider,
                onSaveKey: saveProviderKey
            )
            AIGatewayModelsSection(models: store.settings.models, onUpdate: updateModel, onDelete: deleteModel, onAdd: addModel)
            AIGatewayAgentInstructionsSection(
                settings: store.settings,
                tokenProvider: { store.ensureToken() },
                onApplyClaude: applyClaude,
                onApplyCodex: applyCodex
            )
            AIGatewayLogsSection(logs: runtime.recentLogs)
        }
    }

    private var selectedProviderKeySaved: Bool {
        store.providerKeyStatus(providerID: draft.provider.providerID)
    }

    private var validationMessage: String? {
        AIGatewaySetupConfigurator.validationMessage(draft: draft, hasSavedKey: selectedProviderKeySaved)
    }

    private var setupPlan: AIGatewaySetupPlan {
        AIGatewaySetupPlanner.plan(
            settings: store.settings,
            status: runtime.status,
            installState: installState,
            validationMessage: validationMessage,
            isWorking: isWorking
        )
    }

    private func refresh() {
        installState = AIGatewayClaudeCodeRouterInstaller.state()
        runtime.refreshInstallState()
        draft = AIGatewaySetupDraft.current(settings: store.settings)
    }

    private func runQuickSetup() {
        guard validationMessage == nil, !isWorking else { return }
        isWorking = true
        message = "Applying AI Gateway setup…"
        Task {
            let installed = await ensureInstalled()
            guard installed else {
                isWorking = false
                return
            }
            saveDraftSettings()
            applySelectedAgentConfigs()
            await runtime.restart(settings: store.settings, token: store.ensureToken())
            message = runtime.isRunning ? "AI Gateway is running." : runtime.status.label
            isWorking = false
            installState = AIGatewayClaudeCodeRouterInstaller.state()
            draft = AIGatewaySetupDraft.current(settings: store.settings)
        }
    }

    private func ensureInstalled() async -> Bool {
        let result = await Task.detached { AIGatewayClaudeCodeRouterInstaller.ensureCurrent() }.value
        installState = result.state
        if case .installed = result.state { return true }
        message = result.message
        return false
    }

    private func saveDraftSettings() {
        let configuration = AIGatewaySetupConfigurator.configure(settings: store.settings, draft: draft)
        store.update { $0 = configuration.settings }
        if !configuration.apiKey.isEmpty {
            store.saveProviderKey(configuration.apiKey, providerID: configuration.providerID)
        }
    }

    private func applySelectedAgentConfigs() {
        if draft.useClaude { applyClaude() }
        if draft.useCodex { applyCodex() }
    }

    private func applyClaudeFromDraft() {
        saveDraftSettings()
        applyClaude()
    }

    private func applyCodexFromDraft() {
        saveDraftSettings()
        applyCodex()
    }
}
