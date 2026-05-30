import SwiftUI

struct CodingAgentProcessTopBarButton: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @State private var service = CodingAgentProcessMonitorService.shared
    @State private var showPopover = false
    @State private var hovered = false

    var body: some View {
        Button {
            showPopover.toggle()
            service.refresh(appState: appState, projectStore: projectStore)
        } label: {
            HStack(spacing: 8) {
                KajiIcon(systemName: "cpu", size: 13)
                    .foregroundStyle(iconColor)
                if service.processCount > 0 {
                    Text("\(service.processCount)")
                        .kajiFont(size: 12, weight: .semibold, design: .monospaced)
                        .foregroundStyle(iconColor)
                }
            }
            .padding(.horizontal, service.processCount == 0 ? 7 : 10)
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
        .kajiHoverEffect(isActive: active || service.orphanCount > 0)
        .kajiChangeFeedback(KajiMotion.selectionFeedback, value: showPopover, isEnabled: showPopover)
        .kajiChangeFeedback(KajiMotion.attentionFeedback, value: service.orphanCount, isEnabled: service.orphanCount > 0)
        .kajiPointer()
        .help("Agent Processes")
        .accessibilityLabel("Agent Processes")
        .kajiPopover(isPresented: $showPopover, preferredEdge: .bottom) {
            CodingAgentProcessPanel { showPopover = false }
        }
        .task {
            service.refresh(appState: appState, projectStore: projectStore)
        }
    }

    private var active: Bool {
        showPopover || hovered
    }

    private var iconColor: Color {
        if service.orphanCount > 0 { return KajiTheme.diffRemoveFg }
        return active ? KajiTheme.fg : KajiTheme.fgMuted
    }

    private var borderOpacity: Double {
        ChromeIconButtonStylePolicy.borderOpacity(active: active || service.orphanCount > 0, isTahoe: isTahoe)
    }

    private var isTahoe: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}
