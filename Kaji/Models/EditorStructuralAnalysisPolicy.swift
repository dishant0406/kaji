import Foundation

enum EditorStructuralAnalysisPolicy {
    static let maximumDocumentWideScanUTF16Length = 1_000_000

    @MainActor
    static func allowsDocumentWideScan(_ backingStore: TextBackingStore) -> Bool {
        !backingStore.utf16LengthExceeds(maximumDocumentWideScanUTF16Length)
    }
}
