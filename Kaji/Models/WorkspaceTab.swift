import Foundation

@MainActor
@Observable
final class WorkspaceTab: Identifiable {
    let id: UUID
    var customTitle: String?
    var colorID: String?
    var isPinned: Bool
    var root: SplitNode
    var focusedAreaID: UUID
    var focusHistory: [UUID]

    init(
        id: UUID = UUID(),
        customTitle: String? = nil,
        colorID: String? = nil,
        isPinned: Bool = false,
        root: SplitNode,
        focusedAreaID: UUID,
        focusHistory: [UUID] = []
    ) {
        self.id = id
        self.customTitle = customTitle
        self.colorID = colorID
        self.isPinned = isPinned
        self.root = root
        self.focusedAreaID = focusedAreaID
        self.focusHistory = focusHistory
    }

    var activeArea: TabArea? {
        root.findArea(id: focusedAreaID) ?? root.allAreas().first
    }

    var activeContent: TerminalTab? {
        activeArea?.activeTab
    }

    var title: String {
        customTitle ?? activeContent?.title ?? "Terminal"
    }

    var kind: TerminalTab.Kind {
        activeContent?.kind ?? .terminal
    }

    var hasCustomTitle: Bool {
        customTitle != nil
    }

    var projectPath: String {
        if let area = root.allAreas().first {
            return area.projectPath
        }
        return ""
    }
}
