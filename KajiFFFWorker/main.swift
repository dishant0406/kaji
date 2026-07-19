import Darwin
import FFFKit
import FFFWorkerProtocol
import Foundation

private enum WorkerError: LocalizedError {
    case invalid(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .invalid(message),
             let .failed(message): message
        }
    }
}

private final class FFFLibrary {
    typealias Create = @convention(c) (UnsafePointer<FffCreateOptions>?) -> UnsafeMutablePointer<FffResult>?
    typealias Destroy = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias Wait = @convention(c) (UnsafeMutableRawPointer?, UInt64) -> UnsafeMutablePointer<FffResult>?
    typealias Search = @convention(c) (
        UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UInt32, UInt32, UInt32, Int32, UInt32
    ) -> UnsafeMutablePointer<FffResult>?
    typealias Grep = @convention(c) (
        UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UInt8, UInt64, UInt32, Bool, UInt32, UInt32, UInt64, UInt32, UInt32, Bool
    ) -> UnsafeMutablePointer<FffResult>?
    typealias FreeResult = @convention(c) (UnsafeMutablePointer<FffResult>?) -> Void
    typealias FreeSearch = @convention(c) (UnsafeMutablePointer<FffSearchResult>?) -> Void
    typealias FreeGrep = @convention(c) (UnsafeMutablePointer<FffGrepResult>?) -> Void

    let create: Create
    let destroy: Destroy
    let wait: Wait
    let search: Search
    let grep: Grep
    let freeResult: FreeResult
    let freeSearch: FreeSearch
    let freeGrep: FreeGrep
    private let dylib: UnsafeMutableRawPointer

    init(url: URL) throws {
        guard let dylib = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else {
            throw WorkerError.failed(Self.loaderError())
        }
        do {
            create = try Self.symbol("fff_create_instance_with", in: dylib)
            destroy = try Self.symbol("fff_destroy", in: dylib)
            wait = try Self.symbol("fff_wait_for_scan", in: dylib)
            search = try Self.symbol("fff_search", in: dylib)
            grep = try Self.symbol("fff_live_grep", in: dylib)
            freeResult = try Self.symbol("fff_free_result", in: dylib)
            freeSearch = try Self.symbol("fff_free_search_result", in: dylib)
            freeGrep = try Self.symbol("fff_free_grep_result", in: dylib)
            self.dylib = dylib
        } catch {
            dlclose(dylib)
            throw error
        }
    }

    deinit {
        dlclose(dylib)
    }

    private static func symbol<T>(_ name: String, in dylib: UnsafeMutableRawPointer) throws -> T {
        guard let pointer = dlsym(dylib, name) else { throw WorkerError.failed("Missing FFF symbol: \(name)") }
        return unsafeBitCast(pointer, to: T.self)
    }

    private static func loaderError() -> String {
        guard let value = dlerror() else { return "Unable to load FFF dynamic library" }
        return String(cString: value)
    }
}

private final class FFFIndex {
    private let library: FFFLibrary
    private let handle: UnsafeMutableRawPointer

    init(projectPath: String, databasePath: String, library: FFFLibrary) throws {
        try Self.validatePath(projectPath)
        try Self.validatePath(databasePath)
        try FileManager.default.createDirectory(atPath: databasePath, withIntermediateDirectories: true)
        let frecency = URL(fileURLWithPath: databasePath).appendingPathComponent("frecency").path
        let history = URL(fileURLWithPath: databasePath).appendingPathComponent("history").path
        self.library = library
        var created: UnsafeMutablePointer<FffResult>?
        projectPath.withCString { basePath in
            frecency.withCString { frecencyPath in
                history.withCString { historyPath in
                    var options = FffCreateOptions()
                    options.version = UInt32(FFF_CREATE_OPTIONS_VERSION)
                    options.base_path = basePath
                    options.frecency_db_path = frecencyPath
                    options.history_db_path = historyPath
                    options.enable_mmap_cache = false
                    options.enable_content_indexing = true
                    options.watch = true
                    options.ai_mode = true
                    options.log_file_path = nil
                    options.log_level = nil
                    options.cache_budget_max_files = 0
                    options.cache_budget_max_bytes = 0
                    options.cache_budget_max_file_size = 0
                    options.enable_fs_root_scanning = false
                    options.enable_home_dir_scanning = false
                    options.follow_symlinks = false
                    created = library.create(&options)
                }
            }
        }
        guard let created else { throw WorkerError.failed("FFF create instance returned no result") }
        defer { library.freeResult(created) }
        guard created.pointee.success, let handle = created.pointee.handle else {
            throw WorkerError.failed(Self.message(created, fallback: "FFF create instance failed"))
        }
        self.handle = handle
    }

    deinit {
        library.destroy(handle)
    }

    func warm(timeoutMilliseconds: UInt64) throws {
        guard let result = library.wait(handle, min(timeoutMilliseconds, 60000)) else {
            throw WorkerError.failed("FFF scan returned no result")
        }
        defer { library.freeResult(result) }
        guard result.pointee.success, result.pointee.int_value != 0 else {
            throw WorkerError.failed(Self.message(result, fallback: "FFF scan timed out"))
        }
    }

    func searchFiles(query: String, limit: Int) throws -> [FFFWorkerFileResult] {
        try Self.validateQuery(query)
        let boundedLimit = min(max(limit, 1), 1000)
        try warm(timeoutMilliseconds: 10000)
        let empty = ""
        let result = query.withCString { queryPointer in
            empty.withCString { currentFile in
                library.search(handle, queryPointer, currentFile, 0, 0, UInt32(boundedLimit), 100, 3)
            }
        }
        guard let result else { throw WorkerError.failed("FFF search returned no result") }
        defer { library.freeResult(result) }
        guard result.pointee.success, let raw = result.pointee.handle else {
            throw WorkerError.failed(Self.message(result, fallback: "FFF search failed"))
        }
        let search = raw.assumingMemoryBound(to: FffSearchResult.self)
        defer { library.freeSearch(search) }
        guard let items = search.pointee.items else { return [] }
        return (0 ..< min(Int(search.pointee.count), boundedLimit)).map { offset in
            let item = items.advanced(by: offset).pointee
            return FFFWorkerFileResult(
                relativePath: Self.boundedString(item.relative_path, maximumBytes: 16384),
                fileName: Self.boundedString(item.file_name, maximumBytes: 4096)
            )
        }
    }

    func searchText(query: String, limit: Int) throws -> [FFFWorkerTextMatch] {
        try Self.validateQuery(query)
        let boundedLimit = min(max(limit, 1), 1000)
        try warm(timeoutMilliseconds: 10000)
        let result = query.withCString {
            library.grep(handle, $0, 0, 10 * 1024 * 1024, 30, true, 0, UInt32(boundedLimit), 150, 0, 0, true)
        }
        guard let result else { throw WorkerError.failed("FFF grep returned no result") }
        defer { library.freeResult(result) }
        guard result.pointee.success, let raw = result.pointee.handle else {
            throw WorkerError.failed(Self.message(result, fallback: "FFF grep failed"))
        }
        let grep = raw.assumingMemoryBound(to: FffGrepResult.self)
        defer { library.freeGrep(grep) }
        guard let items = grep.pointee.items else { return [] }
        return (0 ..< min(Int(grep.pointee.count), boundedLimit)).map { offset in
            let item = items.advanced(by: offset).pointee
            return FFFWorkerTextMatch(
                relativePath: Self.boundedString(item.relative_path, maximumBytes: 16384),
                lineContent: Self.boundedString(item.line_content, maximumBytes: 65536),
                lineNumber: item.line_number,
                column: item.col
            )
        }
    }

    private static func validatePath(_ path: String) throws {
        guard !path.isEmpty, path.utf8.count <= 4096, !path.contains("\0"), path.hasPrefix("/") else {
            throw WorkerError.invalid("Invalid absolute path")
        }
    }

    private static func validateQuery(_ query: String) throws {
        guard query.utf8.count <= 65536, !query.contains("\0") else { throw WorkerError.invalid("Invalid search query") }
    }

    private static func boundedString(_ pointer: UnsafePointer<CChar>?, maximumBytes: Int) -> String {
        guard let pointer else { return "" }
        let data = Data(bytes: pointer, count: min(strlen(pointer), maximumBytes))
        return String(decoding: data, as: UTF8.self)
    }

    private static func message(_ result: UnsafeMutablePointer<FffResult>, fallback: String) -> String {
        guard let error = result.pointee.error else { return fallback }
        return String(String(cString: error).prefix(2048))
    }
}

private final class WorkerServer {
    private let library: FFFLibrary
    private var indexes: [String: FFFIndex] = [:]

    init(libraryURL: URL) throws {
        library = try FFFLibrary(url: libraryURL)
    }

    func run() -> Int32 {
        var reader = FFFJSONLineReader(handle: .standardInput, maximumBytes: fffWorkerMaximumRequestBytes)
        while true {
            do {
                let data = try reader.nextFrame()
                let request = try JSONDecoder().decode(FFFWorkerRequest.self, from: data)
                let shouldExit = try respond(to: request)
                if shouldExit { return 0 }
            } catch FFFWorkerProtocolError.endOfFile {
                return 0
            } catch {
                let failure = FFFWorkerResponse(
                    id: UUID(),
                    error: FFFWorkerFailure(code: .invalidRequest, message: error.localizedDescription)
                )
                try? write(failure)
            }
        }
    }

    private func respond(to request: FFFWorkerRequest) throws -> Bool {
        do {
            let result: FFFWorkerResult
            switch request.command {
            case let .create(projectPath, databasePath):
                _ = try index(projectPath: projectPath, databasePath: databasePath)
                result = .acknowledged
            case let .warm(projectPath, timeoutMilliseconds):
                guard let index = indexes[projectPath] else { throw WorkerError.invalid("Index has not been created") }
                try index.warm(timeoutMilliseconds: timeoutMilliseconds)
                result = .acknowledged
            case let .searchFiles(projectPath, query, limit):
                guard let index = indexes[projectPath] else { throw WorkerError.invalid("Index has not been created") }
                result = try .files(index.searchFiles(query: query, limit: limit))
            case let .searchText(projectPath, query, limit):
                guard let index = indexes[projectPath] else { throw WorkerError.invalid("Index has not been created") }
                result = try .textMatches(index.searchText(query: query, limit: limit))
            case let .remove(projectPath):
                indexes.removeValue(forKey: projectPath)
                result = .acknowledged
            case .shutdown:
                indexes.removeAll()
                try write(FFFWorkerResponse(id: request.id, result: .acknowledged))
                return true
            }
            try write(FFFWorkerResponse(id: request.id, result: result))
        } catch let error as WorkerError {
            let code: FFFWorkerFailure.Code = switch error {
            case .invalid: .invalidRequest
            case .failed: .searchFailed
            }
            try write(FFFWorkerResponse(id: request.id, error: FFFWorkerFailure(code: code, message: error.localizedDescription)))
        } catch {
            try write(FFFWorkerResponse(
                id: request.id,
                error: FFFWorkerFailure(code: .internalFailure, message: error.localizedDescription)
            ))
        }
        return false
    }

    private func index(projectPath: String, databasePath: String) throws -> FFFIndex {
        if let index = indexes[projectPath] { return index }
        let index = try FFFIndex(projectPath: projectPath, databasePath: databasePath, library: library)
        indexes[projectPath] = index
        return index
    }

    private func write(_ response: FFFWorkerResponse) throws {
        let data = try FFFJSONLineCodec.encode(response, maximumBytes: fffWorkerMaximumResponseBytes)
        try FileHandle.standardOutput.write(contentsOf: data)
    }
}

guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--library" else {
    FileHandle.standardError.write(Data("usage: KajiFFFWorker --library <path>\n".utf8))
    exit(64)
}

let libraryURL = URL(fileURLWithPath: CommandLine.arguments[2])
do {
    let server = try WorkerServer(libraryURL: libraryURL)
    exit(server.run())
} catch {
    FileHandle.standardError.write(Data("FFF worker startup failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
