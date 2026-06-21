import Foundation
import Testing

@testable import Kaji

@Suite("TabContentMountPolicy")
struct TabContentMountPolicyTests {
    @Test("keeps active and live session tabs mounted")
    func keepsActiveAndLiveSessionTabsMounted() {
        let active = UUID()
        let terminal = UUID()
        let browser = UUID()
        let mounted = TabContentMountPolicy.mountedTabIDs(snapshots: [
            snapshot(active, kind: .editor, isActive: true),
            snapshot(terminal, kind: .terminal),
            snapshot(browser, kind: .browser),
        ])

        #expect(mounted == Set([active, terminal, browser]))
    }

    @Test("keeps modified editors mounted")
    func keepsModifiedEditorsMounted() {
        let clean = UUID()
        let modified = UUID()
        let mounted = TabContentMountPolicy.mountedTabIDs(
            snapshots: [
                snapshot(clean, kind: .editor, length: 10, recencyRank: 0),
                snapshot(modified, kind: .editor, isModified: true, length: 5_000_000, recencyRank: 1),
            ],
            maximumRetainedInactiveCleanEditors: 0
        )

        #expect(mounted == Set([modified]))
    }

    @Test("retains recent clean editors within count and text budget")
    func retainsRecentCleanEditorsWithinBudget() {
        let oldest = UUID()
        let middle = UUID()
        let newest = UUID()
        let oversized = UUID()
        let mounted = TabContentMountPolicy.mountedTabIDs(
            snapshots: [
                snapshot(oldest, kind: .editor, length: 100, recencyRank: 0),
                snapshot(middle, kind: .editor, length: 100, recencyRank: 1),
                snapshot(newest, kind: .editor, length: 100, recencyRank: 2),
                snapshot(oversized, kind: .editor, length: 10_000, recencyRank: 3),
            ],
            maximumRetainedInactiveCleanEditors: 2,
            maximumRetainedInactiveCleanEditorUTF16: 250
        )

        #expect(mounted == Set([middle, newest]))
    }

    private func snapshot(
        _ id: UUID,
        kind: TerminalTab.Kind,
        isActive: Bool = false,
        isModified: Bool = false,
        length: Int? = nil,
        recencyRank: Int = -1
    ) -> TabContentMountSnapshot {
        TabContentMountSnapshot(
            tabID: id,
            kind: kind,
            isActive: isActive,
            isModified: isModified,
            retainedUTF16Length: length,
            recencyRank: recencyRank
        )
    }
}
