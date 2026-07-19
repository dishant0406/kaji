import CryptoKit
import FFFWorkerProtocol
import Foundation

actor FFFSearchIndexStore {
    static let shared = FFFSearchIndexStore()

    private let client: FFFWorkerClient
    private let maximumIndexes: Int
    private var projectPaths = Set<String>()
    private var accessOrder: [String] = []
    private var creations: [String: Task<Void, Error>] = [:]

    init(client: FFFWorkerClient = .shared, maximumIndexes: Int = 4) {
        self.client = client
        self.maximumIndexes = maximumIndexes
    }

    func warm(projectPath: String) async throws {
        try await ensureIndex(projectPath: projectPath)
        do {
            _ = try await client.send(.warm(projectPath: projectPath, timeoutMilliseconds: 10000))
        } catch {
            forget(projectPath)
            throw error
        }
    }

    func searchFiles(projectPath: String, query: String, limit: Int) async throws -> [FileSearchResult] {
        try await ensureIndex(projectPath: projectPath)
        do {
            let result = try await client.send(.searchFiles(projectPath: projectPath, query: query, limit: limit))
            guard case let .files(files) = result else { throw FFFSearchError.invalidWorkerResponse }
            return FFFSearchResultMapper.fileResults(from: files, projectPath: projectPath)
        } catch {
            forget(projectPath)
            throw error
        }
    }

    func searchText(projectPath: String, query: String, limit: Int) async throws -> [ProjectTextSearchMatch] {
        try await ensureIndex(projectPath: projectPath)
        do {
            let result = try await client.send(.searchText(projectPath: projectPath, query: query, limit: limit))
            guard case let .textMatches(matches) = result else { throw FFFSearchError.invalidWorkerResponse }
            return FFFSearchResultMapper.textMatches(from: matches, projectPath: projectPath)
        } catch {
            forget(projectPath)
            throw error
        }
    }

    func remove(projectPaths paths: [String]) async {
        let uniquePaths = Set(paths.filter { !$0.isEmpty })
        for path in uniquePaths {
            creations[path]?.cancel()
            creations.removeValue(forKey: path)
            projectPaths.remove(path)
            accessOrder.removeAll { $0 == path }
        }
        await client.remove(projectPaths: Array(uniquePaths))
    }

    private func forget(_ projectPath: String) {
        projectPaths.remove(projectPath)
        accessOrder.removeAll { $0 == projectPath }
    }

    private func ensureIndex(projectPath: String) async throws {
        guard !projectPath.isEmpty else { throw FFFSearchError.processFailed("Project path is empty") }
        if projectPaths.contains(projectPath) {
            touch(projectPath)
            return
        }
        if let creation = creations[projectPath] {
            try await creation.value
            touch(projectPath)
            return
        }
        let databasePath = Self.databaseURL(projectPath: projectPath).path
        let client = client
        let creation = Task {
            _ = try await client.send(.create(projectPath: projectPath, databasePath: databasePath), timeout: 60)
        }
        creations[projectPath] = creation
        do {
            try await creation.value
            creations.removeValue(forKey: projectPath)
            projectPaths.insert(projectPath)
            touch(projectPath)
            await enforceLimit()
        } catch {
            creations.removeValue(forKey: projectPath)
            throw error
        }
    }

    private func touch(_ projectPath: String) {
        accessOrder.removeAll { $0 == projectPath }
        accessOrder.append(projectPath)
    }

    private func enforceLimit() async {
        while projectPaths.count > maximumIndexes, let oldest = accessOrder.first {
            accessOrder.removeFirst()
            projectPaths.remove(oldest)
            await client.remove(projectPaths: [oldest])
        }
    }

    private static func databaseURL(projectPath: String) -> URL {
        let digest = SHA256.hash(data: Data(projectPath.utf8)).map { String(format: "%02x", $0) }.joined()
        return KajiFileStorage.appSupportDirectory()
            .appendingPathComponent("Search", isDirectory: true)
            .appendingPathComponent("FFF", isDirectory: true)
            .appendingPathComponent("Databases", isDirectory: true)
            .appendingPathComponent(digest, isDirectory: true)
    }
}
