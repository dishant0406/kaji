import Foundation

extension AskOverlay {
    var commitEntries: [AskPaletteEntry]? {
        guard let commitFlow, commitFlow.showsSearchField else { return nil }
        switch commitFlow.stage {
        case .loadingFiles:
            return [commitPlaceholder("Loading changed files", "Reading Git status")]
        case .selectFiles:
            guard !commitFlow.files.isEmpty else {
                return [commitPlaceholder("No changed files", "Working tree is clean")]
            }
            return commitSelectionEntries(commitFlow)
        case .chooseMessageMode:
            return commitMessageModeEntries
        default:
            return nil
        }
    }

    func refreshCommitFlow() {
        guard GitCommandParser.state(for: fieldText)?.command == .commit else { return }
        if commitFlow == nil {
            startCommitFlow()
        }
    }

    func startCommitFlow() {
        guard let selectedWorktree else { return }
        commitFilesTask?.cancel()
        commitFlow = GitCommitFlowState()
        let worktreePath = selectedWorktree.path
        commitFilesTask = Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                do {
                    return try await Result<[GitStatusFile], Error>.success(
                        GitRepositoryService().changedFiles(repoPath: worktreePath)
                    )
                } catch {
                    return Result<[GitStatusFile], Error>.failure(error)
                }
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case let .success(files):
                commitFlow?.files = files
                commitFlow?.stage = .selectFiles
                commitFlow?.statusText = "\(files.count) changed file\(files.count == 1 ? "" : "s")"
            case let .failure(error):
                commitFlow?.stage = .result
                commitFlow?.errorText = error.localizedDescription
            }
            highlightedIndex = entries.isEmpty ? nil : 0
        }
    }

    private func commitSelectionEntries(_ flow: GitCommitFlowState) -> [AskPaletteEntry] {
        let selected = flow.selectedPaths.count
        let all = AskPaletteEntry(
            action: .gitCommitSelectAll,
            title: "All",
            detail: selected == flow.files.count ? "All files selected" : "Select all \(flow.files.count) changed files",
            annotation: selected == flow.files.count ? "Selected" : "Enter"
        )
        return [all] + flow.files.map { file in
            let isSelected = flow.selectedPaths.contains(file.path)
            return AskPaletteEntry(
                action: .gitCommitSelectFile(file.path, selected: isSelected),
                title: file.path,
                detail: "\(isSelected ? "Selected" : "Not selected") • \(file.paletteAnnotationText)",
                annotation: isSelected ? "Selected" : "Enter"
            )
        }
    }

    private var commitMessageModeEntries: [AskPaletteEntry] {
        var result = [
            AskPaletteEntry(
                action: .gitCommitMessageMode(.manual),
                title: GitCommitMessageMode.manual.title,
                detail: "Type the commit message directly",
                annotation: "Enter"
            ),
        ]
        if GitCommitMessageAgent.isAvailable {
            result.insert(AskPaletteEntry(
                action: .gitCommitMessageMode(.generate),
                title: GitCommitMessageMode.generate.title,
                detail: "Show a native draft immediately and refine the message",
                annotation: "Enter"
            ), at: 0)
        }
        return result
    }

    private func commitPlaceholder(_ title: String, _ detail: String) -> AskPaletteEntry {
        AskPaletteEntry(action: .gitPreviewPlaceholder(title), title: title, detail: detail, annotation: nil)
    }
}
