import Foundation

enum EditorViewportRefreshPolicy {
    static func shouldCreateScrollRefreshTask(hasPendingTask: Bool) -> Bool {
        !hasPendingTask
    }

    static func shouldRunScrollRefresh(isEditingViewport: Bool) -> Bool {
        !isEditingViewport
    }
}
