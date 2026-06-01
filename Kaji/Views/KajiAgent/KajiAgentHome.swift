import SwiftUI
import SwiftUIIntrospect

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
    @State private var slashBashCommand = ""
    @State private var didOpenInitialSession = false
    @State private var showingModelPopover = false
    @State private var scrollCoordinator = KajiAgentScrollCoordinator()
    @State private var expandedToolGroups: Set<UUID> = []
    @State private var collapsedToolGroups: Set<UUID> = []
    @State private var timelineHeight: CGFloat = 0
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
            if store.turns.isEmpty {
                emptyState
            } else {
                timeline
            }
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
            store.configure(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore, projectPathOverride: projectPathOverride)
            openInitialSessionIfNeeded()
            requestFocus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openKajiAgentSession)) { notification in
            guard let sessionProjectID = notification.userInfo?["projectID"] as? UUID,
                  sessionProjectID == scope?.projectID,
                  let sessionPath = notification.userInfo?["sessionPath"] as? String
            else { return }
            store.switchSession(path: sessionPath)
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
            KajiPill(title: store.readiness.title, leadingIcon: store.readiness.isReady ? "checkmark.circle" : "exclamationmark.triangle", variant: .plain) {}
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
                widget
            }
            if !store.todoPhases.isEmpty {
                KajiAgentTodoPanel(phases: store.todoPhases)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var timeline: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !store.widgetLines.isEmpty {
                        widget
                            .padding(.bottom, 12)
                    }
                    if !store.todoPhases.isEmpty {
                        KajiAgentTodoPanel(phases: store.todoPhases)
                            .padding(.bottom, 12)
                    }
                    if store.queuedMessageCount > 0 {
                        queuedMessages
                            .padding(.bottom, 12)
                    }
                    ForEach(store.turns) { turn in
                        KajiAgentTurnView(
                            turn: turn,
                            minimumHeight: turn.id == store.turns.last?.id ? max(0, timelineHeight - 24) : nil,
                            expandedToolGroups: $expandedToolGroups,
                            collapsedToolGroups: $collapsedToolGroups
                        )
                            .id(turn.id)
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.bottom, 8)
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { timelineHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, height in timelineHeight = height }
                }
            )
            .introspect(.scrollView, on: .macOS(.v14, .v15, .v26)) { scrollView in
                scrollCoordinator.attach(scrollView)
            }
            if scrollCoordinator.hasUnseenTail {
                Button("Jump to latest") {
                    scrollCoordinator.scrollToBottom(force: true)
                }
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                .padding(.trailing, 14)
                .padding(.bottom, 14)
            }
        }
        .onChange(of: store.turns.last?.id) { _, id in
            guard let id else { return }
            scrollCoordinator.scrollToTurn(id)
        }
        .onChange(of: store.tailVersion) { _, version in
            expandNewToolGroups()
            scrollCoordinator.handleTailChanged()
        }
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
                KajiAgentControlPanel(panel: activePanel, store: store) { self.activePanel = nil }
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

    private func expandNewToolGroups() {
        for group in store.turns.flatMap(\.toolGroups) where !collapsedToolGroups.contains(group.id) {
            expandedToolGroups.insert(group.id)
        }
    }

    private var widget: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(store.widgetLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(KajiTheme.fgDim)
            }
        }
        .padding(12)
        .frame(maxWidth: 760, alignment: .leading)
        .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private var queuedMessages: some View {
        HStack(spacing: 8) {
            KajiIcon(systemName: "tray.full", size: 12)
                .foregroundStyle(KajiTheme.fgMuted)
            Text("\(store.queuedMessageCount) queued message\(store.queuedMessageCount == 1 ? "" : "s")")
                .kajiFont(size: 12, weight: .medium)
                .foregroundStyle(KajiTheme.fgMuted)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: 760, alignment: .leading)
        .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
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
                store.submit(message, attachments: submittedAttachments)
            }
            return
        }
        prompt = ""
        attachments = []
        completionState.clear()
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
        case "model", "models":
            store.requestAvailableModels { _ in }
            activePanel = .models
            return true
        case "login", "auth":
            store.requestLoginProviders { _ in }
            activePanel = .login
            return true
        case "tools":
            store.requestTools()
            activePanel = .tools
            return true
        case "session", "sessions", "resume":
            store.requestSessions(all: args == "all")
            activePanel = .sessions
            return true
        case "settings":
            NotificationCenter.default.post(name: .openParentAgentSettings, object: nil)
            return true
        case "ask":
            store.setSessionPermissionMode(.ask)
            return true
        case "read", "read-allow":
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
        store.switchSession(path: sessionPath)
    }

}
