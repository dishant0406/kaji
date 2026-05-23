import Foundation

enum AskGitPaletteEntries {
    static func build(
        state: GitCommandPaletteState,
        context: AskPaletteContext
    ) -> [AskPaletteEntry] {
        switch state.command {
        case .git:
            guard !state.filter.isEmpty else {
                return GitCommandParser.commonRequests.map(gitCommandEntry)
            }
            return [gitCommandEntry(GitCommandParser.request(command: .git, input: state.filter))]
        case .branch:
            return branchEntries(state: state, context: context)
        case .switchBranch:
            return filteredGitBranches(context.gitBranches, query: state.filter).map { branch in
                AskPaletteEntry(
                    action: .gitSwitchBranch(branch),
                    title: branch,
                    detail: branch == context.currentGitBranch ? "Current branch" : "Switch to this branch",
                    annotation: branch == context.currentGitBranch ? "Current" : "Enter"
                )
            }
        case .checkout:
            let branches = filteredGitBranches(context.gitBranches, query: state.filter).map { branch in
                AskPaletteEntry(
                    action: .gitCheckoutBranch(branch),
                    title: branch,
                    detail: branch == context.currentGitBranch ? "Current branch" : "Checkout this branch",
                    annotation: branch == context.currentGitBranch ? "Current" : "Enter"
                )
            }
            guard !state.filter.isEmpty else { return branches }
            return [gitCommandEntry(GitCommandParser.request(command: .checkout, input: state.filter))] + branches
        case .commit:
            return [
                AskPaletteEntry(
                    action: .gitCommitStart,
                    title: "Start commit",
                    detail: "Select files and write or generate a commit message",
                    annotation: "Enter"
                ),
            ]
        }
    }

    private static func branchEntries(
        state: GitCommandPaletteState,
        context: AskPaletteContext
    ) -> [AskPaletteEntry] {
        let branches = filteredGitBranches(context.gitBranches, query: state.filter).map { branch in
            AskPaletteEntry(
                action: .gitBranch(name: branch, isCurrent: branch == context.currentGitBranch),
                title: branch,
                detail: branch == context.currentGitBranch ? "Current branch" : "Local branch",
                annotation: branch == context.currentGitBranch ? "Current" : "Switch"
            )
        }
        guard branches.isEmpty, context.isLoadingGitBranches else { return branches }
        return [
            .init(
                action: .gitCommand(GitCommandParser.request(arguments: ["branch", "--list"])),
                title: "Loading branches",
                detail: "Reading local branches",
                annotation: nil
            ),
        ]
    }

    private static func gitCommandEntry(_ request: GitCommandRequest) -> AskPaletteEntry {
        let descriptor = GitCommandCatalog.descriptor(for: request.arguments)
        let detail = request.blockedMessage ?? request.confirmationMessage ?? detailText(descriptor)
        let annotation = request.blockedMessage == nil ? "Enter" : "Blocked"
        return .init(action: .gitCommand(request), title: request.displayCommand, detail: detail, annotation: annotation)
    }

    private static func detailText(_ descriptor: GitCommandDescriptor) -> String {
        if descriptor.autoPreviews {
            return "Preview below"
        }
        switch descriptor.effect {
        case .readOnly:
            return "Show command output"
        case .mutating:
            return "Run Git command"
        case .destructive:
            return "Run with confirmation when required"
        case .interactive:
            return "Needs a terminal"
        }
    }

    private static func filteredGitBranches(_ branches: [String], query: String) -> [String] {
        branches.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
    }
}
