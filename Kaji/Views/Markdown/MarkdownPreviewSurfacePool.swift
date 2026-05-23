import Foundation

@MainActor
protocol MarkdownPreviewReusableSurface: AnyObject {
    var ownerID: String? { get set }
    var lastUsed: Date { get set }
    var disposed: Bool { get }
    func prepareForReuse(ownerID: String)
    func dispose()
}

@MainActor
final class MarkdownPreviewSurfacePool<Surface: MarkdownPreviewReusableSurface> {
    private var active: [String: Surface] = [:]
    private var detached: [Surface] = []
    private var warm: Surface?
    private let factory: () -> Surface
    private let now: () -> Date
    private let maxDetached: Int
    private let ttl: TimeInterval

    init(maxDetached: Int = 2, ttl: TimeInterval = 120, now: @escaping () -> Date = Date.init, factory: @escaping () -> Surface) {
        self.factory = factory
        self.now = now
        self.maxDetached = maxDetached
        self.ttl = ttl
    }

    func acquire(ownerID: String) -> Surface {
        if let surface = active[ownerID] {
            return surface
        }
        let surface = matchingDetached(ownerID: ownerID)
            ?? takeWarm()
            ?? takeReusableDetached()
            ?? factory()
        if surface.ownerID != ownerID {
            surface.prepareForReuse(ownerID: ownerID)
        }
        active[ownerID] = surface
        ensureWarmSurface()
        return surface
    }

    func release(ownerID: String) {
        guard let surface = active.removeValue(forKey: ownerID) else { return }
        surface.lastUsed = now()
        detached.append(surface)
        trimDetached()
        ensureWarmSurface()
    }

    func prewarm() {
        ensureWarmSurface()
    }

    func disposeAll() {
        active.values.forEach { $0.dispose() }
        detached.forEach { $0.dispose() }
        warm?.dispose()
        active.removeAll()
        detached.removeAll()
        warm = nil
    }

    var counts: MarkdownPreviewSurfacePoolCounts {
        MarkdownPreviewSurfacePoolCounts(
            active: active.count,
            detached: detached.count,
            warm: warm == nil ? 0 : 1
        )
    }

    private func matchingDetached(ownerID: String) -> Surface? {
        guard let index = detached.firstIndex(where: { $0.ownerID == ownerID }) else { return nil }
        return detached.remove(at: index)
    }

    private func takeWarm() -> Surface? {
        defer { warm = nil }
        return warm
    }

    private func takeReusableDetached() -> Surface? {
        guard !detached.isEmpty else { return nil }
        return detached.removeFirst()
    }

    private func ensureWarmSurface() {
        guard warm == nil else { return }
        warm = factory()
    }

    private func trimDetached() {
        let cutoff = now().addingTimeInterval(-ttl)
        let expired = detached.filter { $0.lastUsed < cutoff }
        detached.removeAll { $0.lastUsed < cutoff }
        expired.forEach { $0.dispose() }
        while detached.count > maxDetached {
            detached.removeFirst().dispose()
        }
    }
}

struct MarkdownPreviewSurfacePoolCounts: Equatable {
    let active: Int
    let detached: Int
    let warm: Int
}
