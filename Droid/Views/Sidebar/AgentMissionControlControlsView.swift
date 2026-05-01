import SwiftUI

private enum AgentMissionControlActionRole {
    case neutral
    case danger
}

struct AgentMissionControlControlsView: View {
    let item: AgentMissionControlItem
    let capabilities: AgentRunCapabilities
    let onReply: ((String) -> Void)?
    let onStop: (() -> Void)?
    let onRestart: (() -> Void)?
    let onResume: (() -> Void)?
    let onVerify: (() -> Void)?
    @State private var replying = false
    @State private var replyText = ""

    var body: some View {
        if hasVisibleControls {
            actionTray
            if replying, let onReply {
                replyComposer(onReply)
            }
        }
    }

    private var actionTray: some View {
        HStack(spacing: 6) {
            replyButton
            resumeButton
            restartButton
            verifyButton
            stopButton
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 45)
        .padding(.vertical, 5)
    }

    @ViewBuilder private var replyButton: some View {
        if onReply != nil, capabilities.reply.isVisible {
            actionButton(title: "Reply", iconName: "arrowshape.turn.up.left", capability: capabilities.reply) {
                replying.toggle()
                if replying {
                    replyText = ""
                }
            }
        }
    }

    @ViewBuilder private var resumeButton: some View {
        if let onResume, capabilities.resume.isVisible {
            actionButton(title: "Resume", iconName: "play", capability: capabilities.resume, action: onResume)
        }
    }

    @ViewBuilder private var restartButton: some View {
        if let onRestart, capabilities.restart.isVisible {
            actionButton(title: "New Run", iconName: "plus", capability: capabilities.restart, action: onRestart)
        }
    }

    @ViewBuilder private var verifyButton: some View {
        if let onVerify, capabilities.verify.isVisible {
            actionButton(
                title: verificationTitle,
                iconName: verificationIconName,
                capability: capabilities.verify,
                action: onVerify
            )
            .disabled(!capabilities.verify.isAvailable || item.verification.status == .running)
        }
    }

    @ViewBuilder private var stopButton: some View {
        if let onStop, capabilities.stop.isVisible {
            actionButton(title: "Stop", iconName: "stop", capability: capabilities.stop, role: .danger, action: onStop)
        }
    }

    private var hasVisibleControls: Bool {
        capabilities.reply.isVisible ||
            capabilities.resume.isVisible ||
            capabilities.restart.isVisible ||
            capabilities.verify.isVisible ||
            capabilities.stop.isVisible
    }

    private func replyComposer(_ onReply: @escaping (String) -> Void) -> some View {
        HStack(spacing: 6) {
            DroidInput(placeholder: "Reply to this run", text: $replyText, width: 230)
            Button("Send") {
                onReply(replyText)
                replyText = ""
                replying = false
            }
            .buttonStyle(DroidButtonStyle(.primary, size: .small))
            .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 45)
        .padding(.bottom, 8)
    }

    private func actionButton(
        title: String,
        iconName: String,
        capability: AgentRunCapability,
        role: AgentMissionControlActionRole = .neutral,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                DroidIcon(systemName: iconName, size: 9)
                Text(title)
                    .droidFont(size: 10, weight: .medium)
            }
            .foregroundStyle(actionColor(role: role, capability: capability))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                DroidTheme.surface.opacity(0.34),
                in: RoundedRectangle(cornerRadius: DroidShape.tileRadius)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!capability.isAvailable)
    }

    private func actionColor(role: AgentMissionControlActionRole, capability: AgentRunCapability) -> Color {
        guard capability.isAvailable else { return DroidTheme.fgDim }
        switch role {
        case .neutral:
            return DroidTheme.fgMuted
        case .danger:
            return DroidTheme.diffRemoveFg
        }
    }

    private var verificationTitle: String {
        switch item.verification.status {
        case .notStarted:
            "Verify run"
        case .running:
            "Verifying..."
        case .passed:
            "Verified"
        case .failed:
            "Rerun verification"
        case .unavailable:
            "Verification unavailable"
        }
    }

    private var verificationIconName: String {
        switch item.verification.status {
        case .passed:
            "checkmark.circle"
        case .failed,
             .unavailable:
            "xmark.circle"
        case .running:
            "clock"
        case .notStarted:
            "play.circle"
        }
    }
}
