import SwiftUI

struct PortMonitorTopBarButton: View {
    @State private var service = PortMonitorService.shared
    @State private var showPopover = false
    @State private var hovered = false

    var body: some View {
        Button {
            showPopover.toggle()
            service.refresh()
        } label: {
            HStack(spacing: 8) {
                KajiIcon(systemName: "network", size: 13)
                    .foregroundStyle(active ? KajiTheme.fg : KajiTheme.fgMuted)
                if !service.ports.isEmpty {
                    Text("\(service.ports.count)")
                        .kajiFont(size: 12, weight: .semibold, design: .monospaced)
                        .foregroundStyle(active ? KajiTheme.fg : KajiTheme.fgMuted)
                }
            }
            .padding(.horizontal, service.ports.isEmpty ? 7 : 10)
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
        .kajiChangeFeedback(KajiMotion.attentionFeedback, value: service.ports.count, isEnabled: !service.ports.isEmpty)
        .kajiPointer()
        .help("Running Ports")
        .accessibilityLabel("Running Ports")
        .kajiPopover(isPresented: $showPopover, preferredEdge: .bottom) {
            PortMonitorPanel {
                showPopover = false
            }
        }
        .task {
            service.refresh()
        }
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
