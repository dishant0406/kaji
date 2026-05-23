import SwiftUI

struct AskOverlay: View {
    let onDismiss: () -> Void

    @Environment(AppState.self) var appState
    @Environment(ProjectStore.self) var projectStore
    @Environment(WorktreeStore.self) var worktreeStore

    @State var fieldText = ""
    @State var prompt = ""
    @State var projectID: UUID?
    @State var worktreeID: UUID?
    @State var provider: AskProvider = .terminal
    @State var sessionMode: AskSessionMode = .bestMatch
    @State var sessionID: UUID?
    @State var highlightedIndex: Int? = 0
    @State var isSending = false
    @State var historyCacheKey: AskHistoryCacheKey?
    @State var cachedHistoryOptions: [AskHistoryOption] = []
    @State var historyLoadTask: Task<Void, Never>?
    @State var isHistoryLoading = false
    @State var taskRecipeStore = AskTaskRecipeStore.shared
    @State var mentionOptions: [AskMentionOption] = []
    @State var mentionLoadTask: Task<Void, Never>?
    @State var directoryOptions: [AskDirectoryOption] = []
    @State var attachments: [AskAttachment] = []
    @State var previewAttachment: AskAttachment?
    @State var isTaskFormVisible = false
    @State var taskFormName = ""
    @State var taskFormPrompt = ""
    @State var taskFormScope = AskTaskRecipeScope.global.rawValue
    @State var editingTaskID: String?
    @State var scriptStore = KajiKitScriptStore.shared
    @State var scriptRunner = KajiKitScriptRunner()
    @State var isScriptFormVisible = false
    @State var scriptDraft = KajiKitScriptDraft()
    @State var scriptPlan: KajiKitScriptRunPlan?
    @State var pendingRiskyScript: KajiKitScript?
    @State var bookmarkStore = AgentSessionBookmarkStore.shared
    @State var selectedBookmarkIDs: Set<UUID> = []
    @State var fallbackBookmarkCandidates: [AgentSessionBookmarkCandidate] = []
    @State var fallbackBookmarkTask: Task<Void, Never>?
    @State var isBookmarkLookupLoading = false
    @State var pendingBookmarkCandidates: [AgentSessionBookmarkCandidate] = []
    @State var isBookmarkFolderPickerVisible = false
    @State var prefillState = AskPrefillState.shared
    @State var diffFiles: [DiffPaletteFile] = []
    @State var diffFilesTask: Task<Void, Never>?
    @State var gitBranches: [String] = []
    @State var currentGitBranch: String?
    @State var isLoadingGitBranches = false
    @State var gitBranchesTask: Task<Void, Never>?
    @State var nativeCommandRunner = NativeCommandRunner()
    @State var pendingGitCommand: GitCommandRequest?

    var body: some View {
        ZStack {
            KajiTheme.bg.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                if nativeCommandRunner.plan != nil {
                    NativeCommandRunnerView(
                        runner: nativeCommandRunner,
                        onStop: stopNativeCommandRun,
                        onClose: finishNativeCommandRun
                    )
                } else if let pendingGitCommand {
                    GitCommandConfirmationView(
                        request: pendingGitCommand,
                        onRun: confirmPendingGitCommand,
                        onCancel: cancelPendingGitCommand
                    )
                } else if scriptPlan != nil {
                    KajiKitScriptRunnerView(runner: scriptRunner, onStop: stopScriptRun, onClose: finishScriptRun)
                } else if isScriptFormVisible {
                    KajiKitScriptForm(draft: $scriptDraft, onSave: saveScriptForm, onCancel: closeScriptForm)
                } else {
                    searchField
                    Divider().overlay(KajiTheme.border.opacity(0.75))
                    targetSummary
                    Divider().overlay(KajiTheme.border.opacity(0.75))
                    if let pendingRiskyScript {
                        KajiKitScriptConfirmationView(
                            script: pendingRiskyScript,
                            onRun: confirmPendingScript,
                            onCancel: cancelPendingScript
                        )
                    } else if isTaskFormVisible {
                        AskTaskRecipeForm(
                            name: $taskFormName,
                            prompt: $taskFormPrompt,
                            scope: $taskFormScope,
                            onSave: saveTaskForm,
                            onCancel: closeTaskForm
                        )
                    } else {
                        if !attachments.isEmpty {
                            AskAttachmentStrip(attachments: attachments, onRemove: removeAttachment, onPreview: { previewAttachment = $0 })
                            Divider().overlay(KajiTheme.border.opacity(0.75))
                        }
                        AskPaletteList(
                            entries: entries,
                            highlightedIndex: highlightedIndex,
                            emptyLabel: emptyLabel,
                            isLoading: isBookmarkLookupLoading,
                            onSelect: apply
                        )
                    }
                    Divider().overlay(KajiTheme.border.opacity(0.75))
                    footer
                }
            }
            .frame(width: modalWidth, height: modalHeight)
            .background(KajiTheme.bg)
            .clipShape(RoundedRectangle(cornerRadius: KajiShape.modalRadius))
            .overlay(
                RoundedRectangle(cornerRadius: KajiShape.modalRadius)
                    .stroke(KajiTheme.borderStrong.opacity(0.82), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityAddTraits(.isModal)
        }
        .overlay { attachmentPreview }
        .background(AskAttachmentDropTarget { attachments.append(contentsOf: $0) })
        .onAppear(perform: configureDefaults)
        .onAppear(perform: applyPrefillIfNeeded)
        .onDisappear {
            diffFilesTask?.cancel()
            gitBranchesTask?.cancel()
        }
        .onChange(of: fieldText) { _, newValue in handleFieldChange(newValue) }
        .onChange(of: projectID) { _, _ in
            syncWorktreeSelection()
            refreshHistoryOptions()
        }
        .onChange(of: worktreeID) { _, _ in refreshHistoryOptions() }
        .onChange(of: provider) { _, _ in
            syncSessionSelection()
            refreshHistoryOptions()
        }
        .onChange(of: sessionMode) { _, _ in syncSessionSelection() }
        .onChange(of: nativeCommandRunner.status) { _, status in handleNativeCommandStatus(status) }
        .background(
            AskOverlayKeyMonitor(
                onSubmit: { handleSubmit(fieldText) },
                onShiftSubmit: { handleShiftSubmit(fieldText) },
                onSpace: handleSpace,
                onEscape: onDismiss,
                onArrowUp: { moveHighlight(-1) },
                onArrowDown: { moveHighlight(1) },
                onPaste: pasteAttachments
            )
        )
    }

    private var modalWidth: CGFloat {
        if nativeCommandRunner.plan != nil { return 780 }
        if pendingGitCommand != nil { return 580 }
        if isScriptFormVisible || scriptPlan != nil { return 780 }
        return 580
    }

    private var modalHeight: CGFloat {
        if nativeCommandRunner.plan != nil { return 520 }
        if pendingGitCommand != nil { return 220 }
        if isScriptFormVisible { return 700 }
        if scriptPlan != nil { return 520 }
        return 420
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            KajiIcon(systemName: isSlashMode || isGitCommandMode ? "command" : "magnifyingglass", size: 12)
                .foregroundStyle(KajiTheme.fgDim)
                .accessibilityHidden(true)
            IconButton(symbol: "paperclip", size: 12, accessibilityLabel: "Attach Image") {
                attachments.append(contentsOf: AskAttachmentLoader.openPanel())
            }
            PaletteSearchField(
                text: $fieldText,
                placeholder: isSlashMode || isGitCommandMode ? "Type a command or option" : "Ask anything or type /",
                fontSize: 14,
                onSubmit: handleSubmit,
                onSubmitText: handleSubmit,
                onShiftSubmitText: handleShiftSubmit,
                onSpace: handleSpace,
                onEscape: onDismiss,
                onArrowUp: { moveHighlight(-1) },
                onArrowDown: { moveHighlight(1) },
                onPaste: pasteAttachments
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var targetSummary: some View {
        HStack(spacing: 8) {
            summaryText(selectedProject?.name ?? "No project")
            separator
            summaryText(selectedWorktreeName)
            separator
            summaryText(provider.title)
            separator
            summaryText(sessionMode.title)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(KajiTheme.bg)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(footerText)
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.fgDim)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var separator: some View {
        Text("•").kajiFont(size: 11).foregroundStyle(KajiTheme.fgDim)
    }

    private func summaryText(_ text: String) -> some View {
        Text(text).kajiFont(size: 11).foregroundStyle(KajiTheme.fgDim).lineLimit(1)
    }

    @ViewBuilder
    private var attachmentPreview: some View {
        if let previewAttachment {
            AskAttachmentPreviewOverlay(attachment: previewAttachment) { self.previewAttachment = nil }
        }
    }
}
