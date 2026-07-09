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
                KajiIcon(systemName: "memorychip", size: 13)
                    .foregroundStyle(active ? KajiTheme.fg : KajiTheme.fgMuted)
                if hasActiveTerminals {
                    Text(memoryText)
                        .kajiFont(size: 12, weight: .semibold, design: .monospaced)
                        .foregroundStyle(active ? KajiTheme.fg : KajiTheme.fgMuted)
                }
            }
            .padding(.horizontal, hasActiveTerminals ? 10 : 7)
            .frame(height: 28)
            .background(active ? KajiTheme.surface : .clear)
            .clipShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
            .overlay {
                RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                    .strokeBorder(KajiTheme.border.opacity(borderOpacity), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        }
        .buttonStyle(.borderless)
        .onHover { hovered = $0 }
        .kajiHoverEffect(isActive: active)
        .kajiChangeFeedback(KajiMotion.selectionFeedback, value: showPopover, isEnabled: showPopover)
        .kajiChangeFeedback(KajiMotion.tapFeedback, value: memoryText)
        .kajiPointer()
        .help("Resource Monitor")
        .accessibilityLabel("Resource Monitor")
        .kajiPopover(isPresented: $showPopover, preferredEdge: .bottom) {
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
        .onChange(of: showPopover) { _, isVisible in
            if isVisible {
                service.refresh(appState: appState, projectStore: projectStore)
            }
        }
        .onDisappear { service.stop() }
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
