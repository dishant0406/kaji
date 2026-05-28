import Foundation
import Testing

@testable import Kaji

@Suite("PaneTabStrip indexed snapshots")
struct PaneTabStripIndexedSnapshotTests {
    @Test("keeps tab identity while precomputing shortcut data")
    @MainActor
    func indexedSnapshots() {
        let tabs = (0 ..< 11).map { index in
            PaneTabStrip.TabSnapshot(
                id: UUID(),
                title: "Tab \(index)",
                kind: .editor,
                isPinned: false,
                hasCustomTitle: false,
                colorID: nil
            )
        }

        let indexed = PaneTabStrip.indexedSnapshots(from: tabs)

        #expect(indexed.map(\.id) == tabs.map(\.id))
        #expect(indexed.prefix(9).map(\.shortcutIndex) == Array(1 ... 9))
        #expect(indexed.prefix(9).allSatisfy { $0.shortcut?.displayString.isEmpty == false })
        #expect(indexed.prefix(9).map { $0.shortcut?.modifiers }.allSatisfy { $0 != nil })
        #expect(indexed[9].shortcutIndex == nil)
        #expect(indexed[10].shortcutIndex == nil)
    }
}
