import SwiftUI

struct CodingAgentProcessRow: View {
    let match: CodingAgentProcessMatch
    let isKilling: Bool
    let onKill: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                KajiBadge(text: badgeText, variant: badgeVariant)
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.process.commandName)
                        .kajiFont(size: 12, weight: .semibold)
                        .foregroundStyle(KajiTheme.fg)
                    Text(detail)
                        .kajiFont(size: 10, design: .monospaced)
                        .foregroundStyle(KajiTheme.fgDim)
                }
                Spacer(minLength: 8)
                Button(action: onKill) {
                    HStack(spacing: 5) {
                        if isKilling {
                            KajiSpinner(size: 10, lineWidth: 1.4)
                        } else {
                            KajiIcon(systemName: "xmark", size: 9)
                        }
                        Text(isKilling ? "Killing" : "Kill")
                    }
                }
                .buttonStyle(KajiButtonStyle(.danger, size: .small))
                .disabled(isKilling)
            }

            Text(match.process.commandLine)
                .kajiFont(size: 10, design: .monospaced)
                .foregroundStyle(KajiTheme.fgDim)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .overlay(
            RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                .strokeBorder(KajiTheme.border.opacity(0.75), lineWidth: 1)
        )
        .kajiChangeFeedback(KajiMotion.attentionFeedback, value: isKilling, isEnabled: isKilling)
    }

    private var badgeText: String {
        match.suspicion.rawValue
    }

    private var badgeVariant: KajiBadgeVariant {
        switch match.suspicion {
        case .active: .accent
        case .orphan: .danger
        case .detached: .warning
        }
    }

    private var detail: String {
        let memory = ByteCountFormatter.string(fromByteCount: Int64(match.process.memoryBytes), countStyle: .memory)
        return "pid \(match.process.pid)  ppid \(match.process.parentPID)  pgid \(match.process.processGroupID)  \(memory)"
    }
}
