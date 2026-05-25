import FFFKit
import Foundation

final class FFFDynamicLibrary: @unchecked Sendable {
    static let shared = FFFDynamicLibrary()

    let createInstance: FFFCreateInstance
    let destroy: FFFDestroy
    let waitForScan: FFFWaitForScan
    let search: FFFSearch
    let liveGrep: FFFLiveGrep
    let freeResult: FFFFreeResult
    let freeSearchResult: FFFFreeSearchResult
    let freeGrepResult: FFFFreeGrepResult

    private let handle: UnsafeMutableRawPointer

    private init() {
        do {
            let url = try FFFSearchBinaryStore.libraryURL()
            guard let handle = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else {
                throw FFFSearchError.processFailed(String(cString: dlerror()))
            }
            self.handle = handle
            createInstance = try Self.symbol("fff_create_instance2", in: handle)
            destroy = try Self.symbol("fff_destroy", in: handle)
            waitForScan = try Self.symbol("fff_wait_for_scan", in: handle)
            search = try Self.symbol("fff_search", in: handle)
            liveGrep = try Self.symbol("fff_live_grep", in: handle)
            freeResult = try Self.symbol("fff_free_result", in: handle)
            freeSearchResult = try Self.symbol("fff_free_search_result", in: handle)
            freeGrepResult = try Self.symbol("fff_free_grep_result", in: handle)
        } catch {
            fatalError(error.localizedDescription)
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
