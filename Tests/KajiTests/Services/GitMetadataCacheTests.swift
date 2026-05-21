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
}
