import CoreGraphics
import Foundation

struct MarkdownEditorAnchorSyncSnapshot: Equatable {
    let activeAnchorID: String?
    let localProgress: Double

    static let empty = MarkdownEditorAnchorSyncSnapshot(activeAnchorID: nil, localProgress: 0)
}
