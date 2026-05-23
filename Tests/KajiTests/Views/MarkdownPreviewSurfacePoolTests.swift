import Foundation
import Testing

@testable import Kaji

@Suite("MarkdownPreviewSurfacePool")
@MainActor
struct MarkdownPreviewSurfacePoolTests {
    @Test("keeps one warm surface after acquire")
    func keepsWarmSurfaceAfterAcquire() {
        var nextID = 0
        let pool = MarkdownPreviewSurfacePool<FakeMarkdownSurface> {
            nextID += 1
            return FakeMarkdownSurface(id: nextID)
        }

        _ = pool.acquire(ownerID: "a")

        #expect(pool.counts == MarkdownPreviewSurfacePoolCounts(active: 1, detached: 0, warm: 1))
        #expect(nextID == 2)
    }

    @Test("reuses matching detached surface")
    func reusesMatchingDetachedSurface() {
        let pool = MarkdownPreviewSurfacePool<FakeMarkdownSurface> {
            FakeMarkdownSurface(id: UUID().hashValue)
        }
        let first = pool.acquire(ownerID: "a")
        pool.release(ownerID: "a")
        let second = pool.acquire(ownerID: "a")

        #expect(first === second)
        #expect(second.reuseOwners == ["a"])
    }

    @Test("disposes detached surfaces above limit")
    func disposesDetachedSurfacesAboveLimit() {
        var created: [FakeMarkdownSurface] = []
        let pool = MarkdownPreviewSurfacePool<FakeMarkdownSurface>(maxDetached: 1) {
            let surface = FakeMarkdownSurface(id: created.count)
            created.append(surface)
            return surface
        }

        _ = pool.acquire(ownerID: "a")
        _ = pool.acquire(ownerID: "b")
        pool.release(ownerID: "a")
        pool.release(ownerID: "b")

        #expect(pool.counts.detached == 1)
        #expect(created.contains { $0.disposed })
    }

    @Test("disposes expired detached surfaces")
    func disposesExpiredDetachedSurfaces() {
        var time = Date(timeIntervalSince1970: 1000)
        let pool = MarkdownPreviewSurfacePool<FakeMarkdownSurface>(ttl: 5, now: { time }) {
            FakeMarkdownSurface(id: UUID().hashValue)
        }
        let surface = pool.acquire(ownerID: "a")
        pool.release(ownerID: "a")
        time = time.addingTimeInterval(10)
        _ = pool.acquire(ownerID: "b")
        pool.release(ownerID: "b")

        #expect(surface.disposed)
    }
}

@MainActor
private final class FakeMarkdownSurface: MarkdownPreviewReusableSurface {
    let id: Int
    var ownerID: String?
    var lastUsed = Date()
    private(set) var disposed = false
    private(set) var reuseOwners: [String] = []

    init(id: Int) {
        self.id = id
    }

    func prepareForReuse(ownerID: String) {
        self.ownerID = ownerID
        reuseOwners.append(ownerID)
    }

    func dispose() {
        disposed = true
    }
}
