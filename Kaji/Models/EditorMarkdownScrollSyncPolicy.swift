import Foundation

enum EditorMarkdownScrollSyncPolicy {
    static let editorToPreviewDebounceNanos: UInt64 = 16_000_000
    static let scrollStabilityTolerance: CGFloat = 0.5

    static func shouldApplyScheduledSync(sourceScrollY: CGFloat, currentScrollY: CGFloat) -> Bool {
        abs(currentScrollY - sourceScrollY) < scrollStabilityTolerance
    }
}
