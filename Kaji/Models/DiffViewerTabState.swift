import Foundation

@MainActor
@Observable
final class DiffViewerTabState: Identifiable {
    let id = UUID()
    let vcs: VCSTabState
    let filePath: String
    let isStaged: Bool
    let projectPath: String
    let files: [GitStatusFile]
    let showsAllChanges: Bool
    var mode: VCSTabState.ViewMode
    var collapsedFilePaths: Set<String> = []
    var comments: [DiffComment] = []

    var displayTitle: String {
        if showsAllChanges { return "All Changes" }
        return (filePath as NSString).lastPathComponent
    }

    init(vcs: VCSTabState, filePath: String = "", isStaged: Bool = false, files: [GitStatusFile] = []) {
        self.vcs = vcs
        self.filePath = filePath
        self.isStaged = isStaged
        self.files = files
        showsAllChanges = !files.isEmpty
        projectPath = vcs.projectPath
        mode = vcs.mode
        loadIfNeeded(forceFull: false)
    }

    func refresh(forceFull: Bool) {
        loadIfNeeded(forceFull: forceFull)
    }

    func isCollapsed(_ filePath: String) -> Bool {
        collapsedFilePaths.contains(filePath)
    }

    func setCollapsed(_ collapsed: Bool, filePath: String) {
        if collapsed {
            collapsedFilePaths.insert(filePath)
        } else {
            collapsedFilePaths.remove(filePath)
        }
    }

    func saveComment(anchor: DiffCommentAnchor, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        comments.removeAll { $0.anchor == anchor }
        comments.append(DiffComment(anchor: anchor, text: trimmed))
    }

    func comment(for anchor: DiffCommentAnchor) -> DiffComment? {
        comments.first { $0.anchor == anchor }
    }

    func comments(for filePath: String) -> [DiffComment] {
        comments.filter { $0.anchor.filePath == filePath }
    }

    var commentPrompt: String {
        var lines = [
            "Please review and address these comments from the diff viewer.",
            "",
        ]
        for comment in comments {
            lines.append("- \(comment.anchor.summary): \(comment.text)")
        }
        return lines.joined(separator: "\n")
    }

    private func loadIfNeeded(forceFull: Bool) {
        if showsAllChanges {
            vcs.ensureDiffsLoaded(files: files, forceFull: forceFull)
            return
        }
        if vcs.files.contains(where: { $0.path == filePath }) {
            vcs.ensureDiffLoaded(filePath: filePath, forceFull: forceFull)
            return
        }
        vcs.loadDiffWithHints(
            filePath: filePath,
            hints: GitRepositoryService.DiffHints(
                hasStaged: isStaged,
                hasUnstaged: !isStaged,
                isUntrackedOrNew: false
            ),
            forceFull: forceFull
        )
    }
}
