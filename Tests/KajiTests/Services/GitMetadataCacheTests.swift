import Foundation
import Testing

@testable import Kaji

@Suite("GitMetadataCache")
struct GitMetadataCacheTests {
    @Test("default branch cache evicts oldest repositories")
    func defaultBranchCacheEvictsOldestRepositories() {
        let cache = GitMetadataCache(maxPRInfoEntries: 4, maxDefaultBranchEntries: 2)

        cache.storeDefaultBranch("main", repoPath: "/repo/one")
        cache.storeDefaultBranch("develop", repoPath: "/repo/two")
        cache.storeDefaultBranch("next", repoPath: "/repo/three")

        #expect(cache.cachedDefaultBranch(repoPath: "/repo/one") == nil)
        #expect(cache.cachedDefaultBranch(repoPath: "/repo/two") == "develop")
        #expect(cache.cachedDefaultBranch(repoPath: "/repo/three") == "next")
    }

    @Test("PR cache evicts oldest repository branch shas")
    func prCacheEvictsOldestEntries() {
        let cache = GitMetadataCache(maxPRInfoEntries: 2, maxDefaultBranchEntries: 4)

        cache.storePRInfo(nil, repoPath: "/repo/one", branch: "main", headSha: "a")
        cache.storePRInfo(nil, repoPath: "/repo/two", branch: "main", headSha: "b")
        cache.storePRInfo(nil, repoPath: "/repo/three", branch: "main", headSha: "c")

        #expect(cache.cachedPRInfo(repoPath: "/repo/one", branch: "main", headSha: "a") == nil)
        #expect(cache.cachedPRInfo(repoPath: "/repo/two", branch: "main", headSha: "b") != nil)
        #expect(cache.cachedPRInfo(repoPath: "/repo/three", branch: "main", headSha: "c") != nil)
    }

    @Test("negative PR cache uses separate short TTL")
    func negativePRCacheExpiresSeparately() {
        let cache = GitMetadataCache(
            maxPRInfoEntries: 4,
            maxDefaultBranchEntries: 4,
            positivePRTTL: 60,
            negativePRTTL: -1
        )

        cache.storePRInfo(nil, repoPath: "/repo/one", branch: "feature", headSha: "a")
        cache.storePRInfo(Self.info(number: 9), repoPath: "/repo/one", branch: "ready", headSha: "b")

        let cachedPositive = cache.cachedPRInfo(repoPath: "/repo/one", branch: "ready", headSha: "b")
        #expect(cache.cachedPRInfo(repoPath: "/repo/one", branch: "feature", headSha: "a") == nil)
        #expect(cachedPositive != nil)
        #expect(cachedPositive!?.number == 9)
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
