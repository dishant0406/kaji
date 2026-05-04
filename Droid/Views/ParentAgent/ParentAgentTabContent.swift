import SwiftUI

struct ParentAgentTabContent: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore

    var body: some View {
        ParentAgentHome { prompt, attachments in
            handlePrompt(prompt, attachments: attachments)
        }
    }

    private func handlePrompt(_ prompt: String, attachments: [AskAttachment]) {
        if ParentAgentController.shared.hasPendingQuestion {
            ParentAgentController.shared.answerPendingQuestion(
                ParentAgentAttachmentFormatter.prompt(prompt, attachments: attachments),
                displayText: prompt.isEmpty ? "Attached files" : prompt,
                attachments: ParentAgentAttachmentFormatter.contexts(attachments)
            )
            return
        }
        ParentAgentController.shared.submit(
            prompt: prompt,
            attachments: attachments,
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
    }
}
