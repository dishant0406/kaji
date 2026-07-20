import SwiftUI

struct KajiCodeGraphAgentSessionView: View {
    let session: KajiCodeGraphAgentSession
    let onClose: () -> Void
    @State private var reply = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(KajiTheme.border).frame(height: 1)
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
                    .kajiFont(size: 13, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                Text(session.status.rawValue)
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            Spacer()
            if session.status == .running || session.status == .planning {
                Button("Stop") {
                    session.controller.stop()
                }
                .buttonStyle(.plain)
                .kajiPointer()
                .kajiFont(size: 12, weight: .medium)
                .foregroundStyle(KajiTheme.diffRemoveFg)
            }
            Button {
                onClose()
            } label: {
                KajiIcon(systemName: "trash", size: 12)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .kajiPointer()
            .foregroundStyle(KajiTheme.fgMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var content: some View {
        VStack(spacing: 12) {
            if let pendingQuestion = session.store.pendingQuestion {
                questionPrompt(pendingQuestion)
            }
            if let task = session.store.activeTask {
                timeline(task)
            } else {
                Text("Waiting for graph-agent activity")
                    .kajiFont(size: 12)
                    .foregroundStyle(KajiTheme.fgDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func questionPrompt(_ pendingQuestion: ParentAgentPendingQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pendingQuestion.question)
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fg)
                .textSelection(.enabled)
            if !pendingQuestion.options.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(pendingQuestion.options) { option in
                        Button(option.title) {
                            session.controller.answerPendingQuestion(option.value, displayText: option.title)
                        }
                        .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 14)
        .padding(.top, 14)
    }

    private func timeline(_ task: ParentAgentTask) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(task.timeline.filter { $0.kind != .user }) { item in
                    timelineItem(item)
                }
            }
            .padding(14)
        }
    }

    private func timelineItem(_ item: ParentAgentTimelineItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            KajiIcon(systemName: iconName(for: item.kind), size: 12)
                .foregroundStyle(color(for: item.kind))
                .frame(width: 16, height: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .kajiFont(size: 12, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .kajiFont(size: 11)
                        .foregroundStyle(KajiTheme.fgMuted)
                        .textSelection(.enabled)
                        .lineLimit(8)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func iconName(for kind: ParentAgentTimelineKind) -> String {
        switch kind {
        case .assistant,
             .final: "sparkles"
        case .thinking: "brain"
        case .childRun: "terminal"
        case .event: "circle"
        case .tool: "wrench"
        case .error: "exclamationmark.triangle"
        case .user: "person"
        }
    }

    private func color(for kind: ParentAgentTimelineKind) -> Color {
        switch kind {
        case .error: KajiTheme.diffRemoveFg
        case .final: KajiTheme.accent
        default: KajiTheme.fgDim
        }
    }

    private var replyBox: some View {
        HStack(spacing: 8) {
            TextField("Reply to Kaji", text: $reply)
                .textFieldStyle(.plain)
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fg)
                .onSubmit(sendReply)
            Button("Send", action: sendReply)
                .buttonStyle(.plain)
                .kajiPointer()
                .kajiFont(size: 12, weight: .semibold)
                .foregroundStyle(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? KajiTheme.fgDim : KajiTheme.accent)
        }
        .padding(10)
        .background(KajiTheme.secondaryBackground)
    }

    private func sendReply() {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        reply = ""
        session.controller.answerPendingQuestion(text)
    }
}
