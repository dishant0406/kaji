import SwiftUI

struct AgentMissionControlChangedFilesView: View {
    let item: AgentMissionControlItem
    let onOpenFile: ((AgentChangedFile) -> Void)?
    let onOpenDiff: ((AgentChangedFile) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
                .kajiFont(size: 10)
                .foregroundStyle(messageColor)
                .lineLimit(2)
            if item.verification.status != .notStarted {
                Text(verificationMessage)
                    .kajiFont(size: 10)
                    .foregroundStyle(verificationColor)
                    .lineLimit(3)
            }
            if !item.changedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.changedFiles.prefix(5)) { file in
                        fileRow(file)
                    }
                    if item.changedFiles.count > 5 {
                        Text("+\(item.changedFiles.count - 5) more")
                            .kajiFont(size: 10, design: .monospaced)
                            .foregroundStyle(KajiTheme.fgDim)
                    }
                }
            }
        }
        .padding(7)
        .background(KajiTheme.surface.opacity(0.42), in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .overlay {
            RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                .strokeBorder(KajiTheme.border.opacity(0.65), lineWidth: 1)
        }
    }

    private func fileRow(_ file: AgentChangedFile) -> some View {
        HStack(spacing: 6) {
            Text(statusText(for: file.status))
                .kajiFont(size: 9, weight: .semibold, design: .monospaced)
                .foregroundStyle(statusColor(for: file.status))
                .frame(width: 14, alignment: .leading)
            Text(file.path)
                .kajiFont(size: 10, design: .monospaced)
                .foregroundStyle(KajiTheme.fgMuted)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(statsText(for: file))
                .kajiFont(size: 9, design: .monospaced)
                .foregroundStyle(KajiTheme.fgDim)
            if let onOpenFile, file.status != .deleted {
                evidenceButton("Open", systemName: "arrow.up.right.square") {
                    onOpenFile(file)
                }
            }
            if let onOpenDiff {
                evidenceButton("Diff", systemName: "doc.text.magnifyingglass") {
                    onOpenDiff(file)
                }
            }
        }
    }

    private func evidenceButton(_ title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                KajiIcon(systemName: systemName, size: 8)
                Text(title)
                    .kajiFont(size: 9, weight: .medium)
            }
            .foregroundStyle(KajiTheme.fgMuted)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(KajiTheme.hover.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .kajiPointer()
    }

    private var message: String {
        switch item.changedFilesAttribution {
        case .providerReported:
            "Provider reported these files for this agent run."
        case .worktreeSnapshot:
            "Snapshot from this worktree after the run completed."
        case .sharedWorktree:
            "Another agent overlapped in this worktree, so exact files are unavailable. Use isolated worktrees for exact attribution."
        case .unavailable:
            "Kaji could not read changed files for this run."
        case .none:
            "No changed-file evidence for this run."
        }
    }

    private var messageColor: Color {
        item.changedFilesAttribution == .sharedWorktree ? KajiTheme.diffHunkFg : KajiTheme.fgDim
    }

    private var verificationMessage: String {
        let command = item.verification.command.map { "`\($0)`" } ?? "verification"
        switch item.verification.status {
        case .notStarted:
            return ""
        case .running:
            return "Running \(command)."
        case .passed:
            return "Passed \(command)."
        case .failed:
            return item.verification.output.map { "Failed \(command): \($0)" } ?? "Failed \(command)."
        case .unavailable:
            return item.verification.output ?? "Verification is unavailable."
        }
    }

    private var verificationColor: Color {
        switch item.verification.status {
        case .passed:
            KajiTheme.diffAddFg
        case .failed,
             .unavailable:
            KajiTheme.diffRemoveFg
        case .running:
            KajiTheme.diffHunkFg
        case .notStarted:
            KajiTheme.fgDim
        }
    }

    private func statusText(for status: AgentChangedFileStatus) -> String {
        switch status {
        case .added:
            "A"
        case .modified:
            "M"
        case .deleted:
            "D"
        case .renamed:
            "R"
        case .copied:
            "C"
        case .untracked:
            "?"
        case .conflicted:
            "U"
        case .unknown:
            "·"
        }
    }

    private func statusColor(for status: AgentChangedFileStatus) -> Color {
        switch status {
        case .added,
             .untracked:
            KajiTheme.diffAddFg
        case .deleted:
            KajiTheme.diffRemoveFg
        case .conflicted:
            KajiTheme.diffHunkFg
        case .modified,
             .renamed,
             .copied,
             .unknown:
            KajiTheme.fgDim
        }
    }

    private func statsText(for file: AgentChangedFile) -> String {
        if file.isBinary { return "binary" }
        let additions = file.additions.map { "+\($0)" } ?? "+?"
        let deletions = file.deletions.map { "-\($0)" } ?? "-?"
        return "\(additions) \(deletions)"
    }
}
