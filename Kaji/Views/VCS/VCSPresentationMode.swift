import Foundation

enum VCSPresentationMode {
    case workspaceTab
    case attachedSidebar

    var showsInlineFileDiffs: Bool {
        self == .workspaceTab
    }
}
