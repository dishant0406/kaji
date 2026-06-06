import Foundation

final class KajiAgentRuntimeLocatorCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedBunLookup: KajiAgentBunLookupResult?
    private var cachedBunLookupDate: Date?

    func bunLookup(ttl: TimeInterval) -> KajiAgentBunLookupResult? {
        lock.lock()
        defer { lock.unlock() }
        guard let cachedBunLookup,
              let cachedBunLookupDate,
              Date().timeIntervalSince(cachedBunLookupDate) < ttl
        else { return nil }
        return cachedBunLookup
    }

    func updateBunLookup(_ result: KajiAgentBunLookupResult) {
        lock.lock()
        cachedBunLookup = result
        cachedBunLookupDate = Date()
        lock.unlock()
    }

    func clear() {
        lock.lock()
        cachedBunLookup = nil
        cachedBunLookupDate = nil
        lock.unlock()
    }
}

enum KajiAgentBunLookupResult: Equatable {
    case found(path: String, version: String?)
    case missing
    case unsupported(String?)
}
