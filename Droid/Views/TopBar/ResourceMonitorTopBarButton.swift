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
                    .foregroundStyle(active ? DroidTheme.fg : DroidTheme.fgMuted)
                if hasActiveTerminals {
                    Text(memoryText)
                        .droidFont(size: 12, weight: .semibold, design: .monospaced)
                        .foregroundStyle(active ? DroidTheme.fg : DroidTheme.fgMuted)
                }
            }
            .padding(.horizontal, hasActiveTerminals ? 10 : 7)
            .frame(height: 28)
            .background(active ? DroidTheme.surface : .clear)
            .clipShape(RoundedRectangle(cornerRadius: DroidShape.tileRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                    .strokeBorder(DroidTheme.border.opacity(borderOpacity), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        }
        .buttonStyle(.borderless)
        .onHover { hovered = $0 }
        .droidPointer()
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

    private var hasActiveTerminals: Bool {
        !service.projects.isEmpty
    }

    private var memoryText: String {
        let total = service.projects.reduce(UInt64(0)) { $0 + $1.memoryBytes }
        guard total > 0 else { return "--" }
        return ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .memory)
    }

    private var active: Bool {
        showPopover || hovered
    }

    private var borderOpacity: Double {
        ChromeIconButtonStylePolicy.borderOpacity(active: active, isTahoe: isTahoe)
    }

    private var isTahoe: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}
