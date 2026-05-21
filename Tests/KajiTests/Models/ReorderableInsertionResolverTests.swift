import CoreGraphics
import Testing

@testable import Kaji

@Suite("ReorderableInsertionResolver")
struct ReorderableInsertionResolverTests {
    @Test("horizontal center before next midpoint keeps item in place")
    func beforeNextMidpointKeepsItem() throws {
        let ids = ["a", "b", "c"]
        let frames = horizontalFrames(ids)

        let offset = ReorderableInsertionResolver.moveOffset(
            orderedIDs: ids,
            frames: frames,
            draggedID: "b",
            dragCenter: 120,
            position: ReorderableHorizontalAxis.position(in:)
        )

        #expect(offset == nil)
    }

    @Test("horizontal center past next midpoint moves forward immediately")
    func pastNextMidpointMovesForward() throws {
        let ids = ["a", "b", "c", "d"]
        let frames = horizontalFrames(ids)

        let offset = ReorderableInsertionResolver.moveOffset(
            orderedIDs: ids,
            frames: frames,
            draggedID: "b",
            dragCenter: 260,
            position: ReorderableHorizontalAxis.position(in:)
        )

        #expect(offset == 3)
    }

    @Test("horizontal center before previous midpoint moves backward")
    func beforePreviousMidpointMovesBackward() throws {
        let ids = ["a", "b", "c", "d"]
        let frames = horizontalFrames(ids)

        let offset = ReorderableInsertionResolver.moveOffset(
            orderedIDs: ids,
            frames: frames,
            draggedID: "d",
            dragCenter: 140,
            position: ReorderableHorizontalAxis.position(in:)
        )

        #expect(offset == 1)
    }

    @Test("vertical center after all midpoints moves to end")
    func afterAllVerticalMidpointsMovesToEnd() throws {
        let ids = ["a", "b", "c"]
        let frames = verticalFrames(ids)

        let offset = ReorderableInsertionResolver.moveOffset(
            orderedIDs: ids,
            frames: frames,
            draggedID: "a",
            dragCenter: 280,
            position: ReorderableVerticalAxis.position(in:)
        )

        #expect(offset == 3)
    }

    private func horizontalFrames(_ ids: [String]) -> [String: CGRect] {
        Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            (id, CGRect(x: index * 100, y: 0, width: 100, height: 40))
        })
    }

    private func verticalFrames(_ ids: [String]) -> [String: CGRect] {
        Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            (id, CGRect(x: 0, y: index * 100, width: 80, height: 100))
        })
    }
}
