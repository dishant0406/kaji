import SwiftUI

struct AgentMissionControlSectionHeader: View {
    let section: AgentMissionControlSection

    var body: some View {
        HStack(spacing: 6) {
            Text(section.kind.title)
                .droidFont(size: 9, weight: .semibold, design: .monospaced)
                .foregroundStyle(DroidTheme.fgDim)
            DroidBadge(text: "\(section.items.count)", variant: badgeVariant)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var badgeVariant: DroidBadgeVariant {
        switch section.kind {
        case .needsAttention:
            .warning
        case .running:
            .accent
        case .failed:
            .danger
        case .completed,
             .notifications:
            .neutral
        }
    }
}

struct AgentMissionControlRow: View {
    let item: AgentMissionControlItem
    let capabilities: AgentRunCapabilities
    let onVerify: (() -> Void)?
    let onOpenFile: ((AgentChangedFile) -> Void)?
    let onOpenDiff: ((AgentChangedFile) -> Void)?
    let onSelect: () -> Void
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
                }
            }
            if capabilities.verify.isVisible, let onVerify {
                verificationAction(onVerify)
            }
        }
        .background(hovered ? DroidTheme.hover : .clear)
        .onHover { hovered = $0 }
        .accessibilityLabel("\(item.title), \(item.status.title)")
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 9) {
            providerIcon
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .droidFont(size: 12, weight: .semibold)
                        .foregroundStyle(DroidTheme.fg)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    DroidBadge(text: item.status.title, variant: badgeVariant)
                }
                Text(item.detail)
                    .droidFont(size: 11)
                    .foregroundStyle(DroidTheme.fgMuted)
                    .lineLimit(2)
                Text(item.providerName)
                    .droidFont(size: 10, design: .monospaced)
                    .foregroundStyle(DroidTheme.fgDim)
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
                DroidIcon(systemName: expanded ? "chevron.down" : "chevron.right", size: 9)
                Text(changedFilesToggleTitle)
                    .droidFont(size: 10, weight: .medium)
                Spacer()
            }
            .foregroundStyle(DroidTheme.fgMuted)
            .padding(.horizontal, 45)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private func verificationAction(_ onVerify: @escaping () -> Void) -> some View {
        Button(action: onVerify) {
            HStack(spacing: 5) {
                DroidIcon(systemName: verificationIconName, size: 9)
                Text(verificationTitle)
                    .droidFont(size: 10, weight: .medium)
                Spacer()
            }
            .foregroundStyle(verificationColor)
            .padding(.horizontal, 45)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!capabilities.verify.isAvailable || item.verification.status == .running)
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

    private var verificationColor: Color {
        switch item.verification.status {
        case .passed:
            DroidTheme.diffAddFg
        case .failed,
             .unavailable:
            DroidTheme.diffRemoveFg
        case .running:
            DroidTheme.diffHunkFg
        case .notStarted:
            DroidTheme.fgMuted
        }
    }

    private var providerIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                .fill(DroidTheme.surface.opacity(0.5))
            ProviderIconView(iconName: item.providerIconName, size: 14, style: .monochrome(DroidTheme.fgMuted))
        }
        .frame(width: 26, height: 26)
        .overlay {
            RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                .strokeBorder(DroidTheme.border.opacity(0.7), lineWidth: 1)
        }
    }

    private var badgeVariant: DroidBadgeVariant {
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
                        .droidFont(size: 8, weight: .semibold, design: .monospaced)
                        .foregroundStyle(DroidTheme.fgDim)
                        .frame(width: 42, alignment: .leading)
                    Text(entry.text)
                        .droidFont(size: 10)
                        .foregroundStyle(DroidTheme.fgMuted)
                        .lineLimit(2)
                }
            }
        }
        .padding(6)
        .background(DroidTheme.surface.opacity(0.38), in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                .strokeBorder(DroidTheme.border.opacity(0.6), lineWidth: 1)
        }
    }
}
