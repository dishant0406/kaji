import Foundation
import Testing

@testable import Kaji

@Suite("TabHistoryPolicy")
struct TabHistoryPolicyTests {
    @Test("recordingVisit appends previous active tab once")
    func recordingVisitAppendsPreviousActiveTabOnce() {
        let first = UUID()
        let second = UUID()
        let history = TabHistoryPolicy.recordingVisit(
            from: first,
            to: second,
            in: [first],
            existingTabIDs: [first, second]
        )

        #expect(history == [first])
    }

    @Test("recordingVisit removes active, stale, and duplicate entries")
    func recordingVisitCompactsInvalidEntries() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let stale = UUID()

        let history = TabHistoryPolicy.recordingVisit(
            from: third,
            to: second,
            in: [first, stale, third, first, second],
            existingTabIDs: [first, second, third]
        )

        #expect(history == [first, third])
    }

    @Test("compacted keeps newest unique entries within the limit")
    func compactedKeepsNewestUniqueEntriesWithinLimit() {
        let ids = (0..<5).map { _ in UUID() }

        let history = TabHistoryPolicy.compacted(
            [ids[0], ids[1], ids[2], ids[1], ids[3], ids[4]],
            activeTabID: ids[4],
            existingTabIDs: Set(ids),
            limit: 3
        )

        #expect(history == [ids[2], ids[1], ids[3]])
    }

    @Test("previousTabID returns newest valid inactive tab")
    func previousTabIDReturnsNewestValidInactiveTab() {
        let first = UUID()
        let second = UUID()
        let third = UUID()

        let previousTabID = TabHistoryPolicy.previousTabID(
            in: [first, second, third],
            activeTabID: third,
            existingTabIDs: [first, second, third]
        )

        #expect(previousTabID == second)
    }
}
