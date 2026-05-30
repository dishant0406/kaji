import SwiftUI

struct AgentMissionControlRow: View {
    let item: AgentMissionControlItem
    let capabilities: AgentRunCapabilities
    let onReply: ((String) -> Void)?
    let onStop: (() -> Void)?
    let onRestart: (() -> Void)?
    let onResume: (() -> Void)?
    let onVerify: (() -> Void)?
    let onOpenFile: ((AgentChangedFile) -> Void)?
    let onOpenDiff: ((AgentChangedFile) -> Void)?
    let onSelect: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onSelect) {
                rowContent
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, item.hasChangedFileEvidence ? 5 : 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .kajiPointer()
            if item.hasChangedFileEvidence {
                evidenceToggle
                if expanded {
                    AgentMissionControlChangedFilesView(
                        item: item,
                        onOpenFile: onOpenFile,
                        onOpenDiff: onOpenDiff
                    )
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .transition(KajiMotion.disclosureTransition(reduceMotion: reduceMotion))
                }
            }
            AgentMissionControlControlsView(
                item: item,
                capabilities: capabilities,
                onReply: onReply,
                onStop: onStop,
                onRestart: onRestart,
                onResume: onResume,
                onVerify: onVerify
            )
        }
        .background(hovered ? KajiTheme.hover : .clear)
        .onHover { hovered = $0 }
        .animation(KajiMotion.fast, value: hovered)
        .animation(KajiMotion.panel, value: expanded)
        .kajiChangeFeedback(KajiMotion.attentionFeedback, value: item.status.title)
        .accessibilityLabel("\(item.title), \(item.status.title)")
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 9) {
            providerIcon
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .kajiFont(size: 12, weight: .semibold)
                        .foregroundStyle(KajiTheme.fg)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    KajiBadge(text: item.status.title, variant: badgeVariant)
                }
                Text(item.detail)
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .lineLimit(2)
                Text(item.providerName)
                    .kajiFont(size: 10, design: .monospaced)
                    .foregroundStyle(KajiTheme.fgDim)
                if !item.transcriptEntries.isEmpty {
                    transcriptPreview
                }
            }
        }
    }

    private var evidenceToggle: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: 5) {
                KajiIcon(systemName: expanded ? "chevron.down" : "chevron.right", size: 9)
                Text(changedFilesToggleTitle)
                    .kajiFont(size: 10, weight: .medium)
                Spacer()
            }
            .foregroundStyle(KajiTheme.fgMuted)
            .padding(.horizontal, 45)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .kajiChangeFeedback(KajiMotion.selectionFeedback, value: expanded)
        .kajiPointer()
    }

    private var changedFilesToggleTitle: String {
        if item.changedFilesAttribution == .none, item.verification.status != .notStarted {
            return "Verification result"
        }
        switch item.changedFilesAttribution {
        case .providerReported:
            return "Files changed by this agent"
        case .worktreeSnapshot:
            return "Files changed in worktree"
        case .sharedWorktree:
            return "Shared worktree attribution"
        case .unavailable:
            return "Changed files unavailable"
        case .none:
            return "Changed files"
        }
    }

    private var providerIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                .fill(KajiTheme.surface.opacity(0.5))
            ProviderIconView(iconName: item.providerIconName, size: 14, style: .monochrome(KajiTheme.fgMuted))
        }
        .frame(width: 26, height: 26)
        .overlay {
            RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                .strokeBorder(KajiTheme.border.opacity(0.7), lineWidth: 1)
        }
    }

    private var badgeVariant: KajiBadgeVariant {
        switch item.status {
        case .running:
            .accent
        case .needsAttention:
            .warning
        case .failed:
            .danger
        case .completed,
             .notice:
            .neutral
        }
    }

    private var transcriptPreview: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(item.transcriptEntries.suffix(3)) { entry in
                HStack(alignment: .top, spacing: 5) {
                    Text(entry.kind.uppercased())
                        .kajiFont(size: 8, weight: .semibold, design: .monospaced)
                        .foregroundStyle(KajiTheme.fgDim)
                        .frame(width: 42, alignment: .leading)
                    Text(entry.text)
                        .kajiFont(size: 10)
                        .foregroundStyle(KajiTheme.fgMuted)
                        .lineLimit(2)
                }
            }
        }
        .padding(6)
        .background(
            KajiTheme.surface.opacity(0.38),
            in: RoundedRectangle(cornerRadius: KajiShape.tileRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                .strokeBorder(KajiTheme.border.opacity(0.6), lineWidth: 1)
        }
    }
}
