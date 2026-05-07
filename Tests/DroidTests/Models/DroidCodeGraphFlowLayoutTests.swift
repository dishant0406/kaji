import CoreGraphics
import Testing

@testable import Droid

struct DroidCodeGraphFlowLayoutTests {
    @Test
    func scattersNodesAndHitTestsCards() {
        let document = DroidCodeGraphDocument(
            projectPath: "/tmp/app",
            builtAt: "2026-05-07T00:00:00Z",
            nodes: [
                DroidCodeGraphNode(id: "a", label: "page.tsx", fileType: "tsx", sourceFile: "app/page.tsx", community: 1, degree: 4),
                DroidCodeGraphNode(id: "b", label: "button.tsx", fileType: "tsx", sourceFile: "components/button.tsx", community: 2, degree: 3),
            ],
            edges: [],
            communities: []
        )

        let layout = DroidCodeGraphFlowLayout(
            document: document,
            nodes: document.nodes,
            viewportSize: CGSize(width: 700, height: 500)
        )

        let firstFrame = layout.nodeFrames["a"]
        let secondFrame = layout.nodeFrames["b"]
        #expect(firstFrame != nil)
        #expect(secondFrame != nil)
        #expect(firstFrame?.origin.x != secondFrame?.origin.x)
        #expect(firstFrame?.origin.y != secondFrame?.origin.y)
        #expect(layout.node(at: layout.nodeFrames["a"]?.center ?? .zero) == "a")
    }

    @Test
    func appliesNodeOffsets() {
        let nodes = (0 ..< 12).map {
            DroidCodeGraphNode(
                id: "\($0)",
                label: "node\($0)",
                fileType: "tsx",
                sourceFile: "src/components/ui/node\($0).tsx",
                community: 1,
                degree: 12 - $0
            )
        }
        let document = DroidCodeGraphDocument(projectPath: "/tmp/app", builtAt: "", nodes: nodes, edges: [], communities: [])
        let layout = DroidCodeGraphFlowLayout(
            document: document,
            nodes: document.nodes,
            viewportSize: CGSize(width: 700, height: 500)
        )
        let movedLayout = DroidCodeGraphFlowLayout(
            document: document,
            nodes: document.nodes,
            viewportSize: CGSize(width: 700, height: 500),
            nodeOffsets: ["0": CGSize(width: 42, height: -20)]
        )

        #expect(movedLayout.nodeFrames["0"]?.origin.x == (layout.nodeFrames["0"]?.origin.x ?? 0) + 42)
        #expect(movedLayout.nodeFrames["0"]?.origin.y == (layout.nodeFrames["0"]?.origin.y ?? 0) - 20)
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
