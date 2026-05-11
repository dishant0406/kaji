import Foundation

enum ResourceMonitorTerminalLocator {
    @MainActor
    static func locate(appState: AppState, projects: [Project]) -> [ResourceMonitorTerminalDescriptor] {
        var descriptors: [ResourceMonitorTerminalDescriptor] = []

        for project in projects {
            for workspaceTab in appState.workspaceTabs(for: project.id) {
                for area in workspaceTab.root.allAreas() {
                    for tab in area.tabs {
                        guard let pane = tab.content.pane else { continue }
                        let folderName = URL(fileURLWithPath: pane.projectPath).lastPathComponent
                        let compactTitle = compactTitle(
                            tab.title,
                            fallbackFolderName: folderName.isEmpty ? project.name : folderName
                        )
                        descriptors.append(
                            ResourceMonitorTerminalDescriptor(
                                paneID: pane.id,
                                tabID: tab.id,
                                areaID: area.id,
                                projectID: project.id,
                                projectName: project.name,
                                title: compactTitle
                            )
                        )
                    }
                }
            }
        }

        return descriptors
    }

    private static func compactTitle(_ rawTitle: String, fallbackFolderName: String) -> String {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallbackFolderName }
        guard trimmed != "Terminal" else { return fallbackFolderName }

        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            let path = (trimmed as NSString).expandingTildeInPath
            let name = URL(fileURLWithPath: path).lastPathComponent
            return name.isEmpty ? fallbackFolderName : name
        }

        return trimmed
    }
}
