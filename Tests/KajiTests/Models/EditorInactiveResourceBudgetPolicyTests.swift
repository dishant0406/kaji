import Foundation
import Testing

@testable import Kaji

@Suite("EditorInactiveResourceBudgetPolicy")
struct EditorInactiveResourceBudgetPolicyTests {
    @Test("releases clean inactive editors beyond count budget")
    func releasesCleanInactiveEditorsBeyondCountBudget() {
        let snapshots = (0 ..< 5).map { index in
            EditorInactiveResourceSnapshot(
                tabID: UUID(),
                isActive: false,
                isModified: false,
                isLoading: false,
                isIncrementalLoading: false,
                retainedUTF16Length: 10,
                recencyRank: index
            )
        }

        let releaseIDs = EditorInactiveResourceBudgetPolicy.tabIDsToRelease(
            snapshots: snapshots,
            maximumRetainedInactiveCleanEditors: 2,
            maximumRetainedInactiveCleanUTF16: 100
        )

        #expect(releaseIDs == Set(snapshots.prefix(3).map(\.tabID)))
    }

    @Test("keeps active and modified editors outside the budget")
    func keepsActiveAndModifiedEditorsOutsideBudget() {
        let activeID = UUID()
        let modifiedID = UUID()
        let olderID = UUID()
        let snapshots = [
            EditorInactiveResourceSnapshot(
                tabID: activeID,
                isActive: true,
                isModified: false,
                isLoading: false,
                isIncrementalLoading: false,
                retainedUTF16Length: 1_000_000,
                recencyRank: 0
            ),
            EditorInactiveResourceSnapshot(
                tabID: modifiedID,
                isActive: false,
                isModified: true,
                isLoading: false,
                isIncrementalLoading: false,
                retainedUTF16Length: 1_000_000,
                recencyRank: 1
            ),
            EditorInactiveResourceSnapshot(
                tabID: olderID,
                isActive: false,
                isModified: false,
                isLoading: false,
                isIncrementalLoading: false,
                retainedUTF16Length: 1_000_000,
                recencyRank: 2
            ),
        ]

        let releaseIDs = EditorInactiveResourceBudgetPolicy.tabIDsToRelease(
            snapshots: snapshots,
            maximumRetainedInactiveCleanEditors: 0,
            maximumRetainedInactiveCleanUTF16: 0
        )

        #expect(releaseIDs == [olderID])
    }

    @Test("releases inactive loading editors")
    func releasesInactiveLoadingEditors() {
        let loadingID = UUID()
        let releaseIDs = EditorInactiveResourceBudgetPolicy.tabIDsToRelease(snapshots: [
            EditorInactiveResourceSnapshot(
                tabID: loadingID,
                isActive: false,
                isModified: false,
                isLoading: true,
                isIncrementalLoading: false,
                retainedUTF16Length: nil,
                recencyRank: 0
            ),
        ])

        #expect(releaseIDs == [loadingID])
    }
}
