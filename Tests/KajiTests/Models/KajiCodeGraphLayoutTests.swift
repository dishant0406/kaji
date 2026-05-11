import CoreGraphics
import Testing

@testable import Kaji

struct KajiCodeGraphLayoutTests {
    @Test
    func appliesNodeOffsetsToHitTesting() {
        let document = KajiCodeGraphDocument(
            projectPath: "/tmp/app",
            builtAt: "2026-05-07T00:00:00Z",
            nodes: [
                KajiCodeGraphNode(id: "a", label: "A", fileType: "swift", sourceFile: nil, community: 1, degree: 2),
                KajiCodeGraphNode(id: "b", label: "B", fileType: "swift", sourceFile: nil, community: 1, degree: 1),
            ],
            edges: [],
            communities: []
        )
        let base = KajiCodeGraphLayout(document: document, size: CGSize(width: 600, height: 400))
        let original = base.positions["a"] ?? .zero
        let moved = KajiCodeGraphLayout(
            document: document,
            size: CGSize(width: 600, height: 400),
            nodeOffsets: ["a": CGSize(width: 42, height: -18)]
        )
        let movedPoint = moved.positions["a"] ?? .zero

        #expect(movedPoint.x == original.x + 42)
        #expect(movedPoint.y == original.y - 18)
        #expect(moved.nearestNode(to: movedPoint, maxDistance: 1) == "a")
    }
}
