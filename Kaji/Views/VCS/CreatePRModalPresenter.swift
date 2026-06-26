import SwiftUI

struct CreatePRModalPresenter: View {
    @Bindable var state: VCSTabState
    let onDismiss: () -> Void

    var body: some View {
        KajiCommandModalShell(width: 620, height: 560, onDismiss: dismiss) {
            CreatePRModal(
                context: .init(
                    currentBranch: state.branchName ?? "",
                    defaultBranch: state.defaultBranch,
                    availableBaseBranches: state.remoteBranches,
                    isLoadingBranches: state.isLoadingRemoteBranches,
                    githubAccounts: state.githubAccounts,
                    isLoadingGitHubAccounts: state.isLoadingGitHubAccounts,
                    hasStagedChanges: state.hasStagedChanges,
                    hasUnstagedChanges: !state.unstagedFiles.isEmpty
                ),
                inProgress: state.isOpeningPullRequest,
                errorMessage: state.openPullRequestError,
                onSubmit: { base, title, body, branchStrategy, includeMode, draft, githubAccount in
                    ToastState.shared.show("Creating pull request…")
                    state.openPullRequest(.init(
                        baseBranch: base,
                        title: title,
                        body: body,
                        branchStrategy: branchStrategy,
                        includeMode: includeMode,
                        draft: draft,
                        githubAccount: githubAccount
                    ))
                },
                onCancel: dismiss
            )
        }
        .onAppear(perform: prepare)
        .onChange(of: state.pullRequestInfo?.number) { _, number in
            guard number != nil else { return }
            onDismiss()
        }
    }

    private func prepare() {
        state.openPullRequestError = nil
        state.loadRemoteBranches()
        state.loadGitHubAccounts()
    }

    private func dismiss() {
        state.openPullRequestError = nil
        onDismiss()
    }
}
