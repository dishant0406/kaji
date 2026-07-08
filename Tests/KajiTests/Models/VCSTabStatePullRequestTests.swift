import Testing

@testable import Kaji

@MainActor
@Suite("VCSTabState pull request events")
struct VCSTabStatePullRequestTests {
    @Test("matching pull request event updates current branch immediately")
    func matchingPullRequestEventUpdatesCurrentBranch() {
        let state = VCSTabState(projectPath: "/tmp/kaji-pr-event")
        let account = GitHubAccount(
            host: "github.com",
            login: "dishant",
            isActive: true,
            state: "success",
            tokenSource: "keyring",
            gitProtocol: "ssh"
        )
        let info = Self.info(number: 42)

        state.branchName = "feature/pr-state"
        state.applyPullRequestStateEvent(PullRequestStateEvent(
            repoPath: "/tmp/kaji-pr-event",
            branch: "feature/pr-state",
            headSha: "abc123",
            info: info,
            account: account
        ))

        #expect(state.pullRequestInfo?.number == 42)
        #expect(state.hasFetchedPullRequestInfo)
        #expect(state.preferredGitHubAccount == account)
        guard case let .hasPR(prInfo) = state.prLaunchState else {
            Issue.record("Expected PR pill state")
            return
        }
        #expect(prInfo.number == 42)
    }

    @Test("different branch pull request event is ignored")
    func differentBranchPullRequestEventIsIgnored() {
        let state = VCSTabState(projectPath: "/tmp/kaji-pr-event")
        state.branchName = "current"
        state.pullRequestInfo = Self.info(number: 5)
        state.hasFetchedPullRequestInfo = true

        state.applyPullRequestStateEvent(PullRequestStateEvent(
            repoPath: "/tmp/kaji-pr-event",
            branch: "other",
            headSha: "abc123",
            info: Self.info(number: 9),
            account: nil
        ))

        #expect(state.pullRequestInfo?.number == 5)
    }

    @Test("matching nil pull request event clears stale PR")
    func matchingNilPullRequestEventClearsStalePR() {
        let state = VCSTabState(projectPath: "/tmp/kaji-pr-event")
        state.branchName = "feature/pr-state"
        state.pullRequestInfo = Self.info(number: 5)
        state.hasFetchedPullRequestInfo = true

        state.applyPullRequestStateEvent(PullRequestStateEvent(
            repoPath: "/tmp/kaji-pr-event",
            branch: "feature/pr-state",
            headSha: "abc123",
            info: nil,
            account: nil
        ))

        #expect(state.pullRequestInfo == nil)
        #expect(state.hasFetchedPullRequestInfo)
    }

    private static func info(number: Int) -> GitRepositoryService.PRInfo {
        GitRepositoryService.PRInfo(
            url: "https://github.com/kaji/kaji/pull/\(number)",
            number: number,
            state: .open,
            isDraft: false,
            baseBranch: "main",
            mergeable: true,
            mergeStateStatus: .clean,
            checks: .init(status: .success, passing: 1, failing: 0, pending: 0, total: 1)
        )
    }
}
