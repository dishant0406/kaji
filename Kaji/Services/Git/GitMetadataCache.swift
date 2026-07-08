import Foundation

final class GitMetadataCache: @unchecked Sendable {
    static let shared = GitMetadataCache()

    struct PRKey: Hashable {
        let repoPath: String
        let branch: String
        let headSha: String
    }

    private struct PREntry {
        let info: GitRepositoryService.PRInfo?
        let storedAt: Date
    }

    private struct DefaultBranchEntry {
        let branch: String?
        let storedAt: Date
    }

    private let lock = NSLock()
    private var prInfo: [PRKey: PREntry] = [:]
    private var defaultBranch: [String: DefaultBranchEntry] = [:]
    private var ghInstalled: Bool?

    private let positivePRTTL: TimeInterval
    private let negativePRTTL: TimeInterval
    private let maxPRInfoEntries: Int
    private let maxDefaultBranchEntries: Int

    init(
        maxPRInfoEntries: Int = 200,
        maxDefaultBranchEntries: Int = 200,
        positivePRTTL: TimeInterval = 60,
        negativePRTTL: TimeInterval = 5
    ) {
        self.maxPRInfoEntries = maxPRInfoEntries
        self.maxDefaultBranchEntries = maxDefaultBranchEntries
        self.positivePRTTL = positivePRTTL
        self.negativePRTTL = negativePRTTL
    }

    func cachedPRInfo(repoPath: String, branch: String, headSha: String) -> GitRepositoryService.PRInfo?? {
        lock.lock()
        defer { lock.unlock() }
        let key = PRKey(repoPath: repoPath, branch: branch, headSha: headSha)
        guard let entry = prInfo[key] else { return nil }
        let ttl = entry.info == nil ? negativePRTTL : positivePRTTL
        if Date().timeIntervalSince(entry.storedAt) > ttl {
            prInfo.removeValue(forKey: key)
            return nil
        }
        return .some(entry.info)
    }

    func storePRInfo(_ info: GitRepositoryService.PRInfo?, repoPath: String, branch: String, headSha: String) {
        lock.lock()
        defer { lock.unlock() }
        let key = PRKey(repoPath: repoPath, branch: branch, headSha: headSha)
        prInfo[key] = PREntry(info: info, storedAt: Date())
        prunePRInfo()
    }

    func invalidatePRInfo(repoPath: String, branch: String) {
        lock.lock()
        defer { lock.unlock() }
        prInfo = prInfo.filter { key, _ in
            !(key.repoPath == repoPath && key.branch == branch)
        }
    }

    func invalidatePRInfo(repoPath: String) {
        lock.lock()
        defer { lock.unlock() }
        prInfo = prInfo.filter { key, _ in key.repoPath != repoPath }
    }

    func cachedDefaultBranch(repoPath: String) -> String?? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = defaultBranch[repoPath] else { return nil }
        defaultBranch[repoPath] = DefaultBranchEntry(branch: entry.branch, storedAt: Date())
        return .some(entry.branch)
    }

    func storeDefaultBranch(_ branch: String?, repoPath: String) {
        lock.lock()
        defer { lock.unlock() }
        defaultBranch[repoPath] = DefaultBranchEntry(branch: branch, storedAt: Date())
        pruneDefaultBranches()
    }

    func cachedGhInstalled() -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return ghInstalled
    }

    func storeGhInstalled(_ installed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        ghInstalled = installed
    }

    private func prunePRInfo() {
        guard prInfo.count > maxPRInfoEntries else { return }
        let overflow = prInfo.count - maxPRInfoEntries
        let oldestKeys = prInfo
            .sorted { $0.value.storedAt < $1.value.storedAt }
            .prefix(overflow)
            .map(\.key)
        for key in oldestKeys {
            prInfo[key] = nil
        }
    }

    private func pruneDefaultBranches() {
        guard defaultBranch.count > maxDefaultBranchEntries else { return }
        let overflow = defaultBranch.count - maxDefaultBranchEntries
        let oldestKeys = defaultBranch
            .sorted { $0.value.storedAt < $1.value.storedAt }
            .prefix(overflow)
            .map(\.key)
        for key in oldestKeys {
            defaultBranch[key] = nil
        }
    }
}
