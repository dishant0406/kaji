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

    var body: some View {
        ZStack {
            DroidTheme.bg.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                searchField
                Divider().overlay(DroidTheme.border.opacity(0.75))
                targetSummary
                Divider().overlay(DroidTheme.border.opacity(0.75))
                if !attachments.isEmpty {
                    AskAttachmentStrip(attachments: attachments, onRemove: removeAttachment, onPreview: { previewAttachment = $0 })
                    Divider().overlay(DroidTheme.border.opacity(0.75))
                }
                if isTaskFormVisible {
                    AskTaskRecipeForm(
                        name: $taskFormName,
                        prompt: $taskFormPrompt,
                        scope: $taskFormScope,
                        onSave: saveTaskForm,
                        onCancel: closeTaskForm
                    )
                } else {
                    AskPaletteList(
                        entries: entries,
                        highlightedIndex: highlightedIndex,
                        emptyLabel: emptyLabel,
                        onSelect: apply
                    )
                }
                Divider().overlay(DroidTheme.border.opacity(0.75))
                footer
            }
            .frame(width: 580, height: 420)
            .background(DroidTheme.bg)
            .clipShape(RoundedRectangle(cornerRadius: DroidShape.modalRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DroidShape.modalRadius)
                    .stroke(DroidTheme.borderStrong.opacity(0.82), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityAddTraits(.isModal)
        }
        .overlay { attachmentPreview }
        .background(AskAttachmentDropTarget { attachments.append(contentsOf: $0) })
        .onAppear(perform: configureDefaults)
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
        .background(
            AskOverlayKeyMonitor(
                onSubmit: { handleSubmit(fieldText) },
                onShiftSubmit: { handleShiftSubmit(fieldText) },
                onEscape: onDismiss,
                onArrowUp: { moveHighlight(-1) },
                onArrowDown: { moveHighlight(1) },
                onPaste: pasteAttachments
            )
        )
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            DroidIcon(systemName: isSlashMode ? "command" : "magnifyingglass", size: 12)
                .foregroundStyle(DroidTheme.fgDim)
                .accessibilityHidden(true)
            IconButton(symbol: "paperclip", size: 12, accessibilityLabel: "Attach Image") {
                attachments.append(contentsOf: AskAttachmentLoader.openPanel())
            }
            PaletteSearchField(
                text: $fieldText,
                placeholder: isSlashMode ? "Type a command or option" : "Ask anything or type /",
                fontSize: 14,
                onSubmit: handleSubmit,
                onSubmitText: handleSubmit,
                onShiftSubmitText: handleShiftSubmit,
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
        .background(DroidTheme.bg)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(footerText)
                .droidFont(size: 11)
                .foregroundStyle(DroidTheme.fgDim)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var separator: some View {
        Text("•").droidFont(size: 11).foregroundStyle(DroidTheme.fgDim)
    }

    private func summaryText(_ text: String) -> some View {
        Text(text).droidFont(size: 11).foregroundStyle(DroidTheme.fgDim).lineLimit(1)
    }

    @ViewBuilder
    private var attachmentPreview: some View {
        if let previewAttachment {
            AskAttachmentPreviewOverlay(attachment: previewAttachment) { self.previewAttachment = nil }
        }
    }
}
