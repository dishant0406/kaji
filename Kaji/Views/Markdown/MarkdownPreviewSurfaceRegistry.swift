import Foundation

@MainActor
final class MarkdownPreviewSurfaceRegistry {
    static let shared = MarkdownPreviewSurfaceRegistry()

    private let pool: MarkdownPreviewSurfacePool<MarkdownPreviewSurface>

    init(pool: MarkdownPreviewSurfacePool<MarkdownPreviewSurface>? = nil) {
        self.pool = pool ?? MarkdownPreviewSurfacePool(factory: MarkdownPreviewSurface.init)
    }

    func prewarm() {
        pool.prewarm()
    }

    func surface(ownerID: String) -> MarkdownPreviewSurface {
        pool.acquire(ownerID: ownerID)
    }

    func release(ownerID: String) {
        pool.release(ownerID: ownerID)
    }

    func disposeAll() {
        pool.disposeAll()
    }

    var counts: MarkdownPreviewSurfacePoolCounts {
        pool.counts
    }
}
