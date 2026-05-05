import SwiftUI

struct ResourceMonitorPanel: View {
    let projects: [ResourceMonitorProjectSnapshot]
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onDismiss: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @State private var service = ResourceMonitorService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if projects.isEmpty {
                Text("No active terminals.")
                    .droidFont(size: 12)
                    .foregroundStyle(DroidTheme.fgDim)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(projects) { project in
                            ResourceMonitorProjectSection(
                                project: project,
                                onCloseTerminal: closeTerminal
                            )
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 360)
        .background(DroidTheme.tertiaryBackground, in: RoundedRectangle(cornerRadius: DroidShape.panelRadius))
        .task {
            service.start(appState: appState, projectStore: projectStore)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            DroidIcon(systemName: "memorychip", size: 12)
                .foregroundStyle(DroidTheme.fgMuted)
            Text("Resource Monitor")
                .droidFont(size: 12, weight: .semibold)
                .foregroundStyle(DroidTheme.fg)

            Spacer(minLength: 8)

            Text("5s")
                .droidFont(size: 10, design: .monospaced)
                .foregroundStyle(DroidTheme.fgDim)

            Button(action: onRefresh) {
                Group {
                    if isRefreshing {
                        DroidSpinner(size: 12, lineWidth: 1.5)
                    } else {
                        DroidIcon(systemName: "arrow.clockwise", size: 11)
                    }
                }
                .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DroidTheme.fgMuted)
            .disabled(isRefreshing)
            .help("Refresh")

            Button(action: onDismiss) {
                DroidIcon(systemName: "xmark", size: 11)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DroidTheme.fgMuted)
            .help("Close")
        }
    }

    private func closeTerminal(_ terminal: ResourceMonitorTerminalSnapshot) {
        appState.closeMonitoredTerminal(
            terminal.tabID,
            areaID: terminal.areaID,
            projectID: terminal.projectID
        )
        service.refresh(appState: appState, projectStore: projectStore)
    }
}
