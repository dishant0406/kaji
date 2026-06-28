import Testing

@testable import Kaji

@Suite("Reorder move destination")
struct ReorderMoveDestinationTests {
    @Test("forward intersection maps to Array move offset after target")
    func forwardIntersectionMapsAfterTarget() {
        #expect(ReorderMoveDestination.arrayMoveOffset(from: 1, to: 2) == 3)
    }

    @Test("backward intersection maps to target offset")
    func backwardIntersectionMapsToTarget() {
        #expect(ReorderMoveDestination.arrayMoveOffset(from: 3, to: 1) == 1)
    }
}
