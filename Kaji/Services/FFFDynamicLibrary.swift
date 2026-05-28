import FFFKit
import Foundation

final class FFFDynamicLibrary: @unchecked Sendable {
    private static let sharedResult: Result<FFFDynamicLibrary, Error> = Result {
        try FFFDynamicLibrary(libraryURL: FFFSearchBinaryStore.libraryURL())
    }

    let createInstance: FFFCreateInstance
    let destroy: FFFDestroy
    let waitForScan: FFFWaitForScan
    let search: FFFSearch
    let liveGrep: FFFLiveGrep
    let freeResult: FFFFreeResult
    let freeSearchResult: FFFFreeSearchResult
    let freeGrepResult: FFFFreeGrepResult

    private let handle: UnsafeMutableRawPointer

    static func load() throws -> FFFDynamicLibrary {
        try sharedResult.get()
    }

    static func load(libraryURL: URL) throws -> FFFDynamicLibrary {
        try FFFDynamicLibrary(libraryURL: libraryURL)
    }

    private init(libraryURL: URL) throws {
        guard let handle = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL) else {
            throw FFFSearchError.processFailed(Self.dynamicLoaderError())
        }
        do {
            let createInstance: FFFCreateInstance = try Self.symbol("fff_create_instance2", in: handle)
            let destroy: FFFDestroy = try Self.symbol("fff_destroy", in: handle)
            let waitForScan: FFFWaitForScan = try Self.symbol("fff_wait_for_scan", in: handle)
            let search: FFFSearch = try Self.symbol("fff_search", in: handle)
            let liveGrep: FFFLiveGrep = try Self.symbol("fff_live_grep", in: handle)
            let freeResult: FFFFreeResult = try Self.symbol("fff_free_result", in: handle)
            let freeSearchResult: FFFFreeSearchResult = try Self.symbol("fff_free_search_result", in: handle)
            let freeGrepResult: FFFFreeGrepResult = try Self.symbol("fff_free_grep_result", in: handle)
            self.handle = handle
            self.createInstance = createInstance
            self.destroy = destroy
            self.waitForScan = waitForScan
            self.search = search
            self.liveGrep = liveGrep
            self.freeResult = freeResult
            self.freeSearchResult = freeSearchResult
            self.freeGrepResult = freeGrepResult
        } catch {
            dlclose(handle)
            throw error
        }
    }

    deinit {
        dlclose(handle)
    }

    private static func symbol<T>(_ name: String, in handle: UnsafeMutableRawPointer) throws -> T {
        guard let pointer = dlsym(handle, name) else {
            throw FFFSearchError.processFailed("Missing FFF symbol: \(name)")
        }
        return unsafeBitCast(pointer, to: T.self)
    }

    private static func dynamicLoaderError() -> String {
        guard let error = dlerror() else { return "Unable to load FFF dynamic library" }
        return String(cString: error)
    }
}

typealias FFFCreateInstance = @convention(c) (
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    Bool,
    Bool,
    Bool,
    Bool,
    Bool,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UInt64,
    UInt64,
    UInt64
) -> UnsafeMutablePointer<FffResult>?

typealias FFFDestroy = @convention(c) (UnsafeMutableRawPointer?) -> Void
typealias FFFWaitForScan = @convention(c) (UnsafeMutableRawPointer?, UInt64) -> UnsafeMutablePointer<FffResult>?
typealias FFFSearch = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UInt32,
    UInt32,
    UInt32,
    Int32,
    UInt32
) -> UnsafeMutablePointer<FffResult>?
typealias FFFLiveGrep = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafePointer<CChar>?,
    UInt8,
    UInt64,
    UInt32,
    Bool,
    UInt32,
    UInt32,
    UInt64,
    UInt32,
    UInt32,
    Bool
) -> UnsafeMutablePointer<FffResult>?
typealias FFFFreeResult = @convention(c) (UnsafeMutablePointer<FffResult>?) -> Void
typealias FFFFreeSearchResult = @convention(c) (UnsafeMutablePointer<FffSearchResult>?) -> Void
typealias FFFFreeGrepResult = @convention(c) (UnsafeMutablePointer<FffGrepResult>?) -> Void
