import Testing

@testable import Kaji

@Suite("Pinned reorder policy")
struct PinnedReorderPolicyTests {
    @Test("unpinned item cannot move before pinned group")
    func unpinnedItemCannotMoveBeforePinnedGroup() {
        let items = [true, false, false]

        let destination = PinnedReorderPolicy.constrainedDestination(
            sourceIndex: 2,
            destination: 0,
            items: items,
            isPinned: { $0 }
        )

        #expect(destination == 1)
    }

    @Test("pinned item cannot move after pinned group")
    func pinnedItemCannotMoveAfterPinnedGroup() {
        let items = [true, true, false]

        let destination = PinnedReorderPolicy.constrainedDestination(
            sourceIndex: 1,
            destination: 3,
            items: items,
            isPinned: { $0 }
        )

        #expect(destination == 2)
    }
}
