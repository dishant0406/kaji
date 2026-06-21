import SwiftUI

struct KajiAgentComposerPanel: View {
    let store: KajiAgentStore
    @Binding var prompt: String
    @Binding var attachments: [AskAttachment]
    @Binding var previewAttachment: AskAttachment?
    @Binding var completionState: AgentComposerCompletionState
    @Binding var activePanel: KajiAgentPanel?
    var isFocused: FocusState<Bool>.Binding
    let thinkingLevel: Binding<String>
    let onSelectSession: (KajiAgentSessionOption) -> Void
    let onRequestFocus: () -> Void
    let onAttach: ([AskAttachment]) -> Void
    let onRemoveAttachment: (AskAttachment) -> Void
    let onStop: () -> Void
    let onSubmit: () -> Void
    let onCompletionMove: (Int) -> Void
    let onCompletionAccept: (Bool) -> Void
    let onCompletionDismiss: () -> Void
    let onPromptChange: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            approvalBar
            questionPrompt
            KajiAgentLoginInstructionsView(store: store)
            attachmentStrip
            controlPanel
            composer
        }
        .onChange(of: prompt) { _, _ in onPromptChange() }
    }

    @ViewBuilder
    private var approvalBar: some View {
        if let approval = store.pendingApproval {
            KajiAgentApprovalBar(request: approval) { option in
                store.answerApproval(approval, option: option)
                onRequestFocus()
            } onCancel: {
                store.cancelApproval(approval)
                onRequestFocus()
            }
        }
    }

    @ViewBuilder
    private var questionPrompt: some View {
        if let question = store.loginQuestion ?? store.pendingQuestion {
            KajiAgentQuestionPrompt(question: question) { answer in
                store.answerQuestion(question, value: answer)
                onRequestFocus()
            } onCancel: {
                store.cancelQuestion(question)
                onRequestFocus()
            }
        }
    }

    @ViewBuilder
    private var attachmentStrip: some View {
        if !attachments.isEmpty {
            AskAttachmentStrip(
                attachments: attachments,
                onRemove: onRemoveAttachment,
                onPreview: { previewAttachment = $0 }
            )
        }
    }

    @ViewBuilder
    private var controlPanel: some View {
        if let activePanel {
            KajiAgentControlPanel(
                panel: activePanel,
                store: store,
                onSelectSession: onSelectSession,
                onClose: { self.activePanel = nil }
            )
        }
    }

    private var composer: some View {
        AgentComposer(
            prompt: $prompt,
            completionState: $completionState,
            isFocused: isFocused,
            placeholder: composerPlaceholder,
            isBusy: composerBusy,
            isReady: store.readiness.isReady,
            hasAttachments: !attachments.isEmpty,
            thinkingLevel: thinkingLevel,
            onAttach: onAttach,
            onStop: onStop,
            onSubmit: onSubmit,
            onCompletionMove: onCompletionMove,
            onCompletionAccept: onCompletionAccept,
            onCompletionDismiss: onCompletionDismiss
        )
    }

    private var composerPlaceholder: String {
        if store.pendingQuestion != nil || store.pendingApproval != nil {
            return "Reply to Kaji Agent"
        }
        return "Ask Kaji Agent to build, fix, review, or research"
    }

    private var composerBusy: Bool {
        store.isRunning && store.pendingQuestion == nil && store.pendingApproval == nil
    }
}
