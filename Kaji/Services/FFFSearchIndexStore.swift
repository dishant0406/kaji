import CryptoKit
import FFFKit
import Foundation

actor FFFSearchIndexStore {
    static let shared = FFFSearchIndexStore()

    private var indexes: [String: FFFSearchIndex] = [:]

    func index(for projectPath: String) throws -> FFFSearchIndex {
        if let index = indexes[projectPath] { return index }
        let index = try FFFSearchIndex(projectPath: projectPath)
        indexes[projectPath] = index
        return index
    }
}

private extension String {
    var fffStableHash: String {
        SHA256.hash(data: Data(utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

final class FFFSearchIndex: @unchecked Sendable {
    private let library: FFFDynamicLibrary
    private let handle: UnsafeMutableRawPointer
    private let projectPath: String

    init(projectPath: String) throws {
        let library = FFFDynamicLibrary.shared
        let empty = ""
        self.projectPath = projectPath
        self.library = library
        let dbDirectory = KajiFileStorage.appSupportDirectory()
            .appendingPathComponent("Search", isDirectory: true)
            .appendingPathComponent("FFF", isDirectory: true)
            .appendingPathComponent("Databases", isDirectory: true)
            .appendingPathComponent(projectPath.fffStableHash, isDirectory: true)
        try FileManager.default.createDirectory(at: dbDirectory, withIntermediateDirectories: true)
        let frecency = dbDirectory.appendingPathComponent("frecency").path
        let history = dbDirectory.appendingPathComponent("history").path

        let result = projectPath.withCString { base in
            frecency.withCString { frecencyPath in
                history.withCString { historyPath in
                    empty.withCString { emptyPath in
                        library.createInstance(
                            base,
                            frecencyPath,
                            historyPath,
                            false,
                            true,
                            true,
                            true,
                            true,
                            emptyPath,
                            emptyPath,
                            0,
                            0,
                            0
                        )
                    }
                }
            }
        }
        guard let result else { throw FFFSearchError.processFailed("FFF create instance returned nil") }
        guard result.pointee.success, let handle = result.pointee.handle else {
            let message = errorMessage(result, fallback: "FFF create instance failed")
            library.freeResult(result)
            throw FFFSearchError.processFailed(message)
        }
        library.freeResult(result)
        self.handle = handle
    }

    deinit {
        library.destroy(handle)
    }

    func waitForScan(timeoutMs: UInt64 = 10000) throws {
        guard let result = library.waitForScan(handle, timeoutMs) else { throw FFFSearchError.processFailed("FFF wait returned nil") }
        defer { library.freeResult(result) }
        guard result.pointee.success else {
            throw FFFSearchError.processFailed(errorMessage(result, fallback: "FFF scan failed"))
        }
    }

    func searchFiles(query: String, limit: Int) throws -> [FileSearchResult] {
        try waitForScan()
        let empty = ""
        guard let result = query.withCString({ queryPath in
            empty.withCString { currentFile in
                library.search(handle, queryPath, currentFile, 0, 0, UInt32(limit), 100, 3)
            }
        })
        else {
            throw FFFSearchError.processFailed("FFF file search returned nil")
        }
        defer { library.freeResult(result) }
        guard result.pointee.success, let raw = result.pointee.handle else {
            throw FFFSearchError.processFailed(errorMessage(result, fallback: "FFF file search failed"))
        }
        let searchResult = raw.assumingMemoryBound(to: FffSearchResult.self)
        defer { library.freeSearchResult(searchResult) }
        return FFFSearchResultMapper.fileResults(from: searchResult, projectPath: projectPath)
    }

    func searchText(query: String, limit: Int) throws -> [ProjectTextSearchMatch] {
        try waitForScan()
        guard let result = query
            .withCString({ library.liveGrep(handle, $0, 0, 10 * 1024 * 1024, 100, true, 0, UInt32(limit), 0, 0, 0, true) })
        else {
            throw FFFSearchError.processFailed("FFF grep returned nil")
        }
        defer { library.freeResult(result) }
        guard result.pointee.success, let raw = result.pointee.handle else {
            throw FFFSearchError.processFailed(errorMessage(result, fallback: "FFF grep failed"))
        }
        let grepResult = raw.assumingMemoryBound(to: FffGrepResult.self)
        defer { library.freeGrepResult(grepResult) }
        return FFFSearchResultMapper.textMatches(from: grepResult, projectPath: projectPath)
    }
}

private func errorMessage(_ result: UnsafeMutablePointer<FffResult>, fallback: String) -> String {
    guard let error = result.pointee.error else { return fallback }
    return String(cString: error)
}
