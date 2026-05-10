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

            if let appSnapshot = service.appSnapshot {
                ResourceMonitorAppRow(app: appSnapshot)
            }

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
            .droidPointer()
            .foregroundStyle(DroidTheme.fgMuted)
            .disabled(isRefreshing)
            .help("Refresh")

            Button(action: onDismiss) {
                DroidIcon(systemName: "xmark", size: 11)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .droidPointer()
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

private struct ResourceMonitorAppRow: View {
    let app: ResourceMonitorAppSnapshot

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.title)
                    .droidFont(size: 12, weight: .semibold)
                    .foregroundStyle(DroidTheme.fg)
                    .lineLimit(1)
                Text(subtitle)
                    .droidFont(size: 10, design: .monospaced)
                    .foregroundStyle(DroidTheme.fgDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            ResourceMetricBadge(text: ResourceMonitorFormatting.cpu(app.cpuPercent))
            ResourceMetricBadge(text: ResourceMonitorFormatting.memory(app.memoryBytes))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(DroidTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                .strokeBorder(DroidTheme.border.opacity(0.8), lineWidth: 1)
        )
    }

    private var subtitle: String {
        [app.processName, "pid \(app.pid)", app.threadCount.map { "\($0)t" }]
            .compactMap(\.self)
            .joined(separator: "  ")
    }
}
