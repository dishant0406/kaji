extension AIGatewaySettingsView {
    func install() {
        run { AIGatewayClaudeCodeRouterInstaller.install() }
    }

    func uninstall() {
        runtime.stop()
        run { AIGatewayClaudeCodeRouterInstaller.uninstall() }
    }

    func run(_ operation: @escaping @Sendable () -> AIGatewayInstallResult) {
        guard !isWorking else { return }
        isWorking = true
        Task.detached {
            let result = operation()
            await MainActor.run {
                installState = result.state
                message = result.message
                isWorking = false
                runtime.refreshInstallState()
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        store.setEnabled(enabled)
        if !enabled { runtime.stop() }
    }

    func setAutoStart(_ enabled: Bool) {
        store.update { $0.autoStart = enabled }
    }

    func setBind(_ bind: String) {
        store.update { $0.bindAddress = bind }
        applyGatewayChange("Saved bind address. Restart gateway to apply it.")
    }

    func setPort(_ port: Int) {
        store.update { $0.port = port }
        applyGatewayChange("Saved port. Restart gateway to apply it.")
    }

    func start() {
        Task { await runtime.start(settings: store.settings, token: store.ensureToken()) }
    }

    func stop() {
        runtime.stop()
        message = "AI Gateway stopped."
    }

    func restart() {
        restartTask?.cancel()
        Task { await runtime.restart(settings: store.settings, token: store.ensureToken()) }
    }

    func rotateToken() {
        store.rotateToken()
        applyGatewayChange("Rotated gateway token. Open new shells to receive the new token.")
    }

    func updateProvider(_ provider: AIGatewayProviderConfiguration) {
        store.updateProvider(provider)
        applyGatewayChange("Saved provider settings. Restart gateway to apply them.")
    }

    func saveProviderKey(_ key: String, _ providerID: String) {
        store.saveProviderKey(key, providerID: providerID)
        applyGatewayChange(key.isEmpty ? "Removed provider key." : "Saved provider key.")
    }

    func updateModel(_ model: AIGatewayModelAlias, _ index: Int) {
        store.update { settings in
            guard settings.models.indices.contains(index) else { return }
            settings.models[index] = model
        }
        applyGatewayChange("Saved model route.")
    }

    func deleteModel(_ index: Int) {
        store.update { settings in
            guard settings.models.count > 1, settings.models.indices.contains(index) else { return }
            settings.models.remove(at: index)
        }
        applyGatewayChange("Deleted model route.")
    }

    func addModel() {
        store.update { settings in
            settings.models.append(AIGatewayModelAlias(
                alias: "model-\(settings.models.count + 1)",
                displayName: "Model",
                routes: ["ollama/qwen2.5-coder:latest"]
            ))
        }
        applyGatewayChange("Added model route.")
    }

    func applyClaude() {
        do {
            try AIGatewayClaudeConnector.install(settings: store.settings)
            message = "Configured Claude Code."
        } catch {
            message = error.localizedDescription
        }
    }

    func applyCodex() {
        do {
            try AIGatewayCodexConnector.install(settings: store.settings)
            message = "Configured Codex."
        } catch {
            message = error.localizedDescription
        }
    }

    func applyGatewayChange(_ savedMessage: String) {
        restartTask?.cancel()
        guard runtime.isRunning else {
            message = savedMessage
            return
        }
        message = "Applying AI Gateway changes…"
        let settings = store.settings
        let token = store.ensureToken()
        restartTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            await runtime.restart(settings: settings, token: token)
            guard !Task.isCancelled else { return }
            message = "Applied AI Gateway changes."
        }
    }
}
