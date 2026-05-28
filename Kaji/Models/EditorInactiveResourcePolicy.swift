import Foundation

@MainActor
enum EditorInactiveResourcePolicy {
    static let retainedCleanDocumentUTF16Limit = 1_000_000

    static func shouldReleaseBackingStore(
        isModified: Bool,
        isLoading: Bool,
        isIncrementalLoading: Bool,
        backingStore: TextBackingStore?
    ) -> Bool {
        guard !isModified else { return false }
        if isLoading || isIncrementalLoading { return true }
        guard let backingStore else { return false }
        return backingStore.utf16LengthExceeds(retainedCleanDocumentUTF16Limit)
    }
}
