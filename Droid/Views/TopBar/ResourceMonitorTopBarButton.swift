import SwiftUI

struct ResourceMonitorTopBarButton: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @State private var service = ResourceMonitorService.shared
    @State private var showPopover = false
    @State private var hovered = false

    var body: some View {
        Button {
            showPopover.toggle()
            service.refresh(appState: appState, projectStore: projectStore)
        } label: {
            HStack(spacing: 8) {
                DroidIcon(systemName: "memorychip", size: 13)
                    .foregroundStyle(showPopover || hovered ? DroidTheme.fg : DroidTheme.fgMuted)
                Text(memoryText)
                    .droidFont(size: 12, weight: .semibold, design: .monospaced)
                    .foregroundStyle(showPopover || hovered ? DroidTheme.fg : DroidTheme.fgMuted)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(showPopover || hovered ? DroidTheme.surface : DroidTheme.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: DroidShape.tileRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                    .strokeBorder(DroidTheme.border.opacity(showPopover || hovered ? 1 : 0.65), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Resource Monitor")
        .accessibilityLabel("Resource Monitor")
        .droidPopover(isPresented: $showPopover, preferredEdge: .bottom) {
            ResourceMonitorPanel(
                projects: service.projects,
                isRefreshing: service.isRefreshing,
                onRefresh: { service.refresh(appState: appState, projectStore: projectStore) },
                onDismiss: { showPopover = false }
            )
        }
        .task {
            service.start(appState: appState, projectStore: projectStore)
        }
    }

    private var memoryText: String {
        let total = service.projects.reduce(UInt64(0)) { $0 + $1.memoryBytes }
        guard total > 0 else { return "--" }
        return ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .memory)
    }
}
