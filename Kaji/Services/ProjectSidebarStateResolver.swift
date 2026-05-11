import Foundation

@MainActor
enum ProjectSidebarStateResolver {
    static func hasOpenTerminal(projectID: UUID, appState: AppState) -> Bool {
        appState.workspaceTabs(for: projectID).contains { workspaceTab in
            workspaceTab.root.allAreas().contains { area in
                area.tabs.contains { $0.kind == .terminal }
            }
        }
    }
}
