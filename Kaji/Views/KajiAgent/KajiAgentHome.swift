import SwiftUI

struct KajiAgentHome: View {
    let scope: KajiAgentScope?
    let initialSessionPath: String?
    var projectPathOverride: String?
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @State private var store: KajiAgentStore
    @State private var prompt = ""
    @State private var attachments: [AskAttachment] = []
    @State private var previewAttachment: AskAttachment?
    @State private var completionState = AgentComposerCompletionState()
    @State private var completionTask: Task<Void, Never>?
    @State private var activePanel: KajiAgentPanel?
    @State private var didOpenInitialSession = false
    @State private var showingModelPopover = false
    @State private var pendingSessionSwitchPath: String?
    @FocusState private var focused

    init(scope: KajiAgentScope? = nil, projectPathOverride: String? = nil, initialSessionPath: String? = nil) {
        self.scope = scope
        self.initialSessionPath = initialSessionPath
        self.projectPathOverride = projectPathOverride ?? scope?.projectPath
        _store = State(initialValue: scope.map { KajiAgentStoreRegistry.shared.store(for: $0) } ?? KajiAgentStore())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 18)
                .padding(.bottom, 14)
                .frame(maxWidth: 760, alignment: .leading)
                .background(KajiTheme.bg)
                .zIndex(1)
            transcriptSurface
            composer
                .frame(maxWidth: 720)
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 88)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KajiTheme.bg)
        .overlay { attachmentPreview }
        .background(AskAttachmentDropTarget { attachments.append(contentsOf: $0) })
        .onAppear {
            store.configure(
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore,
                projectPathOverride: projectPathOverride
            )
            openInitialSessionIfNeeded()
            requestFocus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openKajiAgentSession)) { notification in
            guard matchesSessionNotification(notification),
                  let sessionPath = notification.userInfo?["sessionPath"] as? String
            else { return }
            requestSessionSwitch(path: sessionPath)
        }
        .alert("Stop current Kaji Agent run?", isPresented: confirmsSessionSwitch) {
            Button("Cancel", role: .cancel) { pendingSessionSwitchPath = nil }
            Button("Stop and Open", role: .destructive) { confirmSessionSwitch() }
        } message: {
            Text("Opening this history session will stop the current Kaji Agent run.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            KajiPill(title: store.modelLabel, leadingIcon: "sparkles", trailingIcon: "chevron.down", variant: .filled) {
                store.requestModelConfig { _ in }
                showingModelPopover.toggle()
            }
            .kajiPopover(isPresented: $showingModelPopover, preferredEdge: .bottom) {
                modelPopover
            }
            .help(store.statusMessage)
            KajiPill(title: store.effectivePermissionMode.title, leadingIcon: "lock", variant: .plain) {}
                .help(store.effectivePermissionMode.detail)
            KajiPill(title: "New thread", leadingIcon: "plus", variant: .plain, action: startNewThread)
            KajiPill(
                title: store.readiness.title,
                leadingIcon: store.readiness.isReady ? "checkmark.circle" : "exclamationmark.triangle",
                variant: .plain
            ) {
                store.retryRuntimeReadiness()
            }
            .help(store.readiness.detail)
            Spacer(minLength: 0)
        }
    }

    private var modelPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Model")
                    .kajiFont(size: 12, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                Spacer(minLength: 0)
                Button { store.requestModelConfig { _ in } } label: {
                    KajiIcon(systemName: "arrow.clockwise", size: 11)
                        .foregroundStyle(KajiTheme.fgMuted)
                }
                .buttonStyle(.plain)
                .kajiPointer()
                .help("Refresh models")
            }
            SearchableListPicker(
                items: store.modelOptions,
                filterKey: { "\($0.title) \($0.provider) \($0.modelID) \($0.id)" },
                placeholder: "Search models",
                emptyLabel: "No models",
                emptyActionTitle: nil,
                emptyActionDetail: nil,
                onEmptyAction: nil,
                onSelect: { option in
                    store.setModel(provider: option.provider, modelID: option.modelID)
                    showingModelPopover = false
                },
                row: { option, highlighted in
                    HStack(spacing: 10) {
                        KajiIcon(systemName: highlighted ? "checkmark.circle" : "sparkles", size: 12)
                            .foregroundStyle(KajiTheme.fgMuted)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                                .kajiFont(size: 12, weight: .medium)
                                .foregroundStyle(KajiTheme.fg)
                                .lineLimit(1)
                            Text(option.id)
                                .kajiFont(size: 11)
                                .foregroundStyle(KajiTheme.fgDim)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            )
            .frame(height: 320)
        }
        .padding(10)
        .frame(width: 360)
    }

    private var emptyState: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            Text("What do you want Kaji Agent to do?")
                .kajiFont(size: 19, weight: .medium)
                .foregroundStyle(KajiTheme.fg)
            if !store.widgetLines.isEmpty {
                KajiAgentWidgetLinesView(lines: store.widgetLines)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var restoringState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            KajiSpinner(size: 14)
            Text("Loading thread")
                .kajiFont(size: 13, weight: .medium)
                .foregroundStyle(KajiTheme.fgMuted)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transcriptSurface: some View {
        ZStack(alignment: .bottomTrailing) {
            timeline
                .opacity(store.turns.isEmpty ? 0 : 1)
                .allowsHitTesting(!store.turns.isEmpty)
            if store.turns.isEmpty {
                if store.isRestoringTranscript {
                    restoringState
                } else {
                    emptyState
                }
            }
        }
    }

    private var timeline: some View {
        KajiAgentTimelineView(store: store, floatingTaskState: floatingTaskState)
    }

    private var floatingTaskState: KajiAgentFloatingTaskState {
        KajiAgentFloatingTaskState(todoPhases: store.todoPhases, turns: store.turns, isAgentRunning: store.isRunning)
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if let question = store.loginQuestion ?? store.pendingQuestion {
                KajiAgentQuestionPrompt(question: question) { answer in
                    store.answerQuestion(question, value: answer)
                    requestFocus()
                } onCancel: {
                    store.cancelQuestion(question)
                    requestFocus()
                }
            }
            KajiAgentLoginInstructionsView(store: store)
            if !attachments.isEmpty {
                AskAttachmentStrip(attachments: attachments, onRemove: removeAttachment, onPreview: { previewAttachment = $0 })
            }
            if let activePanel {
                KajiAgentControlPanel(
                    panel: activePanel,
                    store: store,
                    onSelectSession: { requestSessionSwitch(path: $0.path) },
                    onClose: { self.activePanel = nil }
                )
            }
            AgentComposer(
                prompt: $prompt,
                completionState: $completionState,
                isFocused: $focused,
                placeholder: store.pendingQuestion == nil ? "Ask Kaji Agent to build, fix, review, or research" : "Reply to Kaji Agent",
                isBusy: store.isRunning && store.pendingQuestion == nil,
                isReady: store.readiness.isReady,
                hasAttachments: !attachments.isEmpty,
                thinkingLevel: thinkingSelection,
                onAttach: attach,
                onStop: stop,
                onSubmit: submit,
                onCompletionMove: moveCompletion,
                onCompletionAccept: { acceptCompletion(submitAfterAccept: $0) },
                onCompletionDismiss: { completionState.clear() }
            )
        }
        .onChange(of: prompt) { _, _ in refreshCompletions() }
    }

    @ViewBuilder
    private var attachmentPreview: some View {
        if let previewAttachment {
            AskAttachmentPreviewOverlay(attachment: previewAttachment) { self.previewAttachment = nil }
        }
    }

    private func startNewThread() {
        prompt = ""
        attachments = []
        completionState.clear()
        store.clear()
        requestFocus()
    }

    private var confirmsSessionSwitch: Binding<Bool> {
        Binding(
            get: { pendingSessionSwitchPath != nil },
            set: { isPresented in
                if !isPresented { pendingSessionSwitchPath = nil }
            }
        )
    }

    private func matchesSessionNotification(_ notification: Notification) -> Bool {
        guard let scope else { return false }
        guard let sessionProjectID = notification.userInfo?["projectID"] as? UUID,
              sessionProjectID == scope.projectID
        else { return false }
        if let worktreeID = notification.userInfo?["worktreeID"] as? UUID, worktreeID != scope.worktreeID {
            return false
        }
        if let agentID = notification.userInfo?["agentID"] as? UUID, agentID != scope.agentID {
            return false
        }
        return true
    }

    private func requestSessionSwitch(path: String) {
        guard !store.isRunning else {
            pendingSessionSwitchPath = path
            return
        }
        store.switchSession(path: path)
    }

    private func confirmSessionSwitch() {
        guard let path = pendingSessionSwitchPath else { return }
        pendingSessionSwitchPath = nil
        store.switchSession(path: path)
    }

    private func attach(_ newAttachments: [AskAttachment]) {
        attachments.append(contentsOf: newAttachments)
        requestFocus()
    }

    private func removeAttachment(_ attachment: AskAttachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    private func stop() {
        store.stop()
        requestFocus()
    }

    private func submit() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedAttachments = attachments
        guard !text.isEmpty || !submittedAttachments.isEmpty else { return }
        if handleNativeSlash(text) {
            prompt = ""
            attachments = []
            completionState.clear()
            return
        }
        if let slashSkill = skillInvocation(in: text) {
            prompt = ""
            attachments = []
            completionState.clear()
            store.buildSkillPrompt(name: slashSkill.name, args: slashSkill.args) { message in
                guard let message else { return }
                store.markUserSubmittedScrollIntent()
                store.submit(message, attachments: submittedAttachments)
            }
            return
        }
        prompt = ""
        attachments = []
        completionState.clear()
        store.markUserSubmittedScrollIntent()
        store.submit(text, attachments: submittedAttachments)
    }

    private func requestFocus() {
        focused = false
        DispatchQueue.main.async { focused = true }
    }

    private var thinkingSelection: Binding<String> {
        Binding(get: { store.thinkingLevel }, set: { store.setThinkingLevel($0) })
    }

    private func refreshCompletions() {
        completionTask?.cancel()
        let currentPrompt = prompt
        let projectPath = projectPathOverride ?? activeWorktreePath()
        let slashCommands = store.slashCommands
        let skills = store.skills
        let history = store.recentHistory
        completionTask = Task { @MainActor in
            let state = await AgentComposerCompletionProvider.state(
                for: currentPrompt,
                projectPath: projectPath,
                slashCommands: slashCommands,
                skills: skills,
                history: history
            )
            guard !Task.isCancelled, currentPrompt == prompt else { return }
            completionState = state
        }
    }

    private func moveCompletion(_ delta: Int) {
        guard completionState.isVisible else { return }
        let count = completionState.suggestions.count
        completionState.highlightedIndex = (completionState.highlightedIndex + delta + count) % count
    }

    private func acceptCompletion(submitAfterAccept requestedSubmit: Bool) {
        guard completionState.isVisible,
              completionState.suggestions.indices.contains(completionState.highlightedIndex)
        else { return }
        let suggestion = completionState.suggestions[completionState.highlightedIndex]
        if suggestion.id == "action:copy-prompt" {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prompt, forType: .string)
            completionState.clear()
            return
        }
        if suggestion.id == "action:clear" {
            prompt = ""
            completionState.clear()
            return
        }
        prompt = AgentComposerCompletionProvider.apply(suggestion, to: prompt, state: completionState)
        completionState.clear()
        if requestedSubmit, suggestion.submitOnEnter {
            DispatchQueue.main.async { submit() }
            return
        }
        requestFocus()
    }

    private func skillInvocation(in text: String) -> (name: String, args: String)? {
        guard text.hasPrefix("/skill:") else { return nil }
        let body = String(text.dropFirst("/skill:".count))
        let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard let name = parts.first, !name.isEmpty else { return nil }
        return (String(name), parts.count > 1 ? String(parts[1]) : "")
    }

    private func handleNativeSlash(_ text: String) -> Bool {
        guard text.hasPrefix("/") else { return false }
        let body = String(text.dropFirst())
        let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let command = parts.first.map { String($0).lowercased() } ?? ""
        let args = parts.count > 1 ? String(parts[1]) : ""
        switch command {
        case "model",
             "models":
            store.requestAvailableModels { _ in }
            activePanel = .models
            return true
        case "login",
             "auth":
            store.requestLoginProviders { _ in }
            activePanel = .login
            return true
        case "tools":
            store.requestTools()
            activePanel = .tools
            return true
        case "session",
             "sessions",
             "resume":
            store.requestSessions(all: args == "all")
            activePanel = .sessions
            return true
        case "settings":
            NotificationCenter.default.post(name: .openParentAgentSettings, object: nil)
            return true
        case "ask":
            store.setSessionPermissionMode(.ask)
            return true
        case "read",
             "read-allow":
            store.setSessionPermissionMode(.readAllow)
            return true
        case "bypass":
            store.setSessionPermissionMode(.bypass)
            return true
        case "new":
            startNewThread()
            return true
        case "compact":
            store.compact(customInstructions: args.nilIfEmpty)
            return true
        case "handoff":
            store.handoff(customInstructions: args.nilIfEmpty)
            return true
        case "bash":
            if args.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            store.executeBash(args)
            return true
        default:
            return false
        }
    }

    private func activeWorktreePath() -> String? {
        guard let projectID = appState.activeProjectID,
              let project = projectStore.projects.first(where: { $0.id == projectID })
        else { return nil }
        worktreeStore.ensurePrimary(for: project)
        guard let key = appState.activeWorktreeKey(for: project.id) else { return project.path }
        return worktreeStore.worktree(projectID: project.id, worktreeID: key.worktreeID)?.path ?? project.path
    }

    private func openInitialSessionIfNeeded() {
        guard !didOpenInitialSession, let sessionPath = initialSessionPath else { return }
        didOpenInitialSession = true
        requestSessionSwitch(path: sessionPath)
    }
}
