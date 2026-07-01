import Foundation

actor FileSearchIndex {
    private struct CacheEntry {
        let files: [FileSearchResult]
        let loadedAt: Date
        let accessedAt: Date

        func isFresh(cacheLifetime: TimeInterval) -> Bool {
            loadedAt.timeIntervalSinceNow >= -cacheLifetime
        }
    }

    private var cache: [String: CacheEntry] = [:]
    private var warmTasks: [String: Task<[FileSearchResult], Never>] = [:]
    private let cacheLifetime: TimeInterval
    private let maxCachedProjects: Int
    private let maxFilesPerProject: Int

    init(cacheLifetime: TimeInterval = 300, maxCachedProjects: Int = 8, maxFilesPerProject: Int = 20000) {
        self.cacheLifetime = cacheLifetime
        self.maxCachedProjects = max(1, maxCachedProjects)
        self.maxFilesPerProject = max(1, maxFilesPerProject)
    }

    deinit {
        warmTasks.values.forEach { $0.cancel() }
    }

    func cachedFiles(in projectPath: String) -> [FileSearchResult]? {
        pruneExpiredCache()
        guard let entry = cache[projectPath], entry.isFresh(cacheLifetime: cacheLifetime) else {
            cache.removeValue(forKey: projectPath)
            return nil
        }
        touch(projectPath, entry: entry)
        return entry.files
    }

    func files(in projectPath: String) async -> [FileSearchResult] {
        pruneExpiredCache()
        if let entry = cache[projectPath], entry.isFresh(cacheLifetime: cacheLifetime) {
            touch(projectPath, entry: entry)
            return entry.files
        }

        if let task = warmTasks[projectPath] {
            return await task.value
        }

        return await startWarmTask(for: projectPath)
    }

    func initialFiles(in projectPath: String, maxDepth: Int, limit: Int) async -> [FileSearchResult] {
        await FileSearchScanner.scanShallow(in: projectPath, maxDepth: maxDepth, limit: limit)
    }

    func warm(projectPath: String) async {
        pruneExpiredCache()
        if let entry = cache[projectPath], entry.isFresh(cacheLifetime: cacheLifetime) {
            touch(projectPath, entry: entry)
            return
        }

        if let task = warmTasks[projectPath] {
            _ = await task.value
            return
        }

        _ = await startWarmTask(for: projectPath)
    }

    private func startWarmTask(for projectPath: String) async -> [FileSearchResult] {
        let task = Task { await FileSearchScanner.scanAll(in: projectPath, limit: maxFilesPerProject) }
        warmTasks[projectPath] = task
        let files = await task.value
        let now = Date()
        cache[projectPath] = CacheEntry(files: files, loadedAt: now, accessedAt: now)
        warmTasks[projectPath] = nil
        enforceCacheLimit()
        return files
    }

    private func touch(_ projectPath: String, entry: CacheEntry) {
        cache[projectPath] = CacheEntry(files: entry.files, loadedAt: entry.loadedAt, accessedAt: Date())
    }

    private func pruneExpiredCache() {
        cache = cache.filter { $0.value.isFresh(cacheLifetime: cacheLifetime) }
    }

    private func enforceCacheLimit() {
        guard cache.count > maxCachedProjects else { return }
        let keep = Set(cache.sorted { lhs, rhs in
            lhs.value.accessedAt > rhs.value.accessedAt
        }.prefix(maxCachedProjects).map(\.key))
        cache = cache.filter { keep.contains($0.key) }
    }
}
