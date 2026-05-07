import SwiftUI

struct DroidCodeGraphAgentSessionView: View {
    let session: DroidCodeGraphAgentSession
    let onClose: () -> Void
    @State private var reply = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(DroidTheme.border).frame(height: 1)
            content
            if session.store.pendingQuestion?.options.isEmpty == true {
                replyBox
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .droidFont(size: 13, weight: .semibold)
                    .foregroundStyle(DroidTheme.fg)
                Text(session.status.rawValue)
                    .droidFont(size: 11)
                    .foregroundStyle(DroidTheme.fgDim)
            }
            Spacer()
            if session.status == .running || session.status == .planning {
                Button("Stop") {
                    session.controller.stop()
                }
                .buttonStyle(.plain)
                .droidFont(size: 12, weight: .medium)
                .foregroundStyle(DroidTheme.diffRemoveFg)
            }
            Button {
                onClose()
            } label: {
                DroidIcon(systemName: "trash", size: 12)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DroidTheme.fgMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var content: some View {
        VStack(spacing: 12) {
            if let pendingQuestion = session.store.pendingQuestion {
                ParentAgentQuestionPrompt(pendingQuestion: pendingQuestion) { option in
                    session.controller.answerPendingQuestion(option.value, displayText: option.title)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
            }
            if let task = session.store.activeTask {
                ParentAgentTimelineView(task: task, showsUserMessages: false)
                    .padding(.horizontal, 14)
            } else {
                Text("Waiting for graph-agent activity")
                    .droidFont(size: 12)
                    .foregroundStyle(DroidTheme.fgDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var replyBox: some View {
        HStack(spacing: 8) {
            TextField("Reply to Droid", text: $reply)
                .textFieldStyle(.plain)
                .droidFont(size: 12)
                .foregroundStyle(DroidTheme.fg)
                .onSubmit(sendReply)
            Button("Send", action: sendReply)
                .buttonStyle(.plain)
                .droidFont(size: 12, weight: .semibold)
                .foregroundStyle(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? DroidTheme.fgDim : DroidTheme.accent)
        }
        .padding(10)
        .background(DroidTheme.secondaryBackground)
    }

    private func sendReply() {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        reply = ""
        session.controller.answerPendingQuestion(text)
    }
}
