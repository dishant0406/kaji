import SwiftUI

struct ParentAgentHome: View {
    var onSubmit: (String, [AskAttachment]) -> Void
    @State private var prompt = ""
    @State private var attachments: [AskAttachment] = []
    @State private var previewAttachment: AskAttachment?
    @State private var taskStore = ParentAgentTaskStore.shared
    @FocusState private var focused

    var body: some View {
        VStack(spacing: 0) {
            if let task = taskStore.activeTask {
                VStack(spacing: 0) {
                    ParentAgentHeaderControls(task: task, onNewThread: startNewTask, showsNewThread: true)
                        .padding(.top, 18)
                        .padding(.bottom, 14)
                        .frame(maxWidth: 760, alignment: .leading)
                        .background(DroidTheme.bg)
                        .zIndex(1)
                    ParentAgentTimelineView(task: task)
                }
                composer
                    .frame(maxWidth: 720)
            } else {
                ZStack(alignment: .topLeading) {
                    ParentAgentHeaderControls(task: nil, onNewThread: startNewTask, showsNewThread: false)
                        .padding(.top, 18)
                    VStack(spacing: 22) {
                        Spacer(minLength: 0)
                        Text("What do you want to do?")
                            .droidFont(size: 19, weight: .medium)
                            .foregroundStyle(DroidTheme.fg)
                        composer
                            .frame(maxWidth: 640)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 88)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DroidTheme.bg)
        .overlay { attachmentPreview }
        .background(AskAttachmentDropTarget { attachments.append(contentsOf: $0) })
        .onAppear { focused = true }
        .onChange(of: taskStore.activeTask?.status) { _, status in
            guard status == .completed || status == .waitingForUser else { return }
            focused = true
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if let pendingQuestion = taskStore.pendingQuestion {
                ParentAgentQuestionPrompt(pendingQuestion: pendingQuestion) { option in
                    ParentAgentController.shared.answerPendingQuestion(option.value, displayText: option.title)
                }
            }
            if !attachments.isEmpty {
                AskAttachmentStrip(attachments: attachments, onRemove: removeAttachment, onPreview: { previewAttachment = $0 })
            }
            ParentAgentComposer(
                prompt: $prompt,
                isFocused: $focused,
                placeholder: promptPlaceholder,
                isBusy: isBusy,
                isReady: isReady,
                hasAttachments: !attachments.isEmpty,
                onAttach: attach,
                onStop: stopParentAgent,
                onSubmit: submit
            )
        }
    }

    @ViewBuilder
    private var attachmentPreview: some View {
        if let previewAttachment {
            AskAttachmentPreviewOverlay(attachment: previewAttachment) { self.previewAttachment = nil }
        }
    }

    private var promptPlaceholder: String {
        taskStore.pendingQuestion == nil ? "What do you want to build, fix, or review?" : "Reply to Droid"
    }

    private var isBusy: Bool {
        guard taskStore.pendingQuestion == nil else { return false }
        guard let status = taskStore.activeTask?.status else { return false }
        return status == .planning || status == .running
    }

    private var isReady: Bool {
        ParentAgentSettingsStore.shared.readiness.isReady
    }

    private func startNewTask() {
        prompt = ""
        attachments = []
        taskStore.clearActiveTask()
        focused = true
    }

    private func attach(_ newAttachments: [AskAttachment]) {
        attachments.append(contentsOf: newAttachments)
        focused = true
    }

    private func removeAttachment(_ attachment: AskAttachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    private func stopParentAgent() {
        ParentAgentController.shared.stop()
        focused = true
    }

    private func submit() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedAttachments = attachments
        guard !text.isEmpty || !submittedAttachments.isEmpty else { return }
        prompt = ""
        attachments = []
        if taskStore.pendingQuestion != nil {
            ParentAgentController.shared.answerPendingQuestion(
                ParentAgentAttachmentFormatter.prompt(text, attachments: submittedAttachments),
                displayText: text.isEmpty ? "Attached files" : text,
                attachments: ParentAgentAttachmentFormatter.contexts(submittedAttachments)
            )
            return
        }
        onSubmit(text, submittedAttachments)
    }
}
