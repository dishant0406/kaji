import SwiftUI

struct AIUsageTopBarButton: View {
    @AppStorage(AIUsageSettingsStore.usageEnabledKey) private var usageEnabled = false
    @AppStorage(AIUsageSettingsStore.usageDisplayModeKey) private var usageDisplayModeRaw =
        AIUsageSettingsStore.defaultUsageDisplayMode.rawValue
    @AppStorage(AIUsageSettingsStore.sidebarPreviewProviderIDKey) private var pinnedPreviewProviderID = ""
    @State private var service = AIUsageService.shared
    @State private var showPopover = false
    @State private var hovered = false

    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if usageEnabled {
                button
            }
        }
        .task {
            await service.refreshIfNeeded()
        }
        .onReceive(refreshTimer) { _ in
            Task {
                await service.refreshIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleAIUsage)) { _ in
            guard usageEnabled else { return }
            showPopover.toggle()
        }
        .onChange(of: usageEnabled) { _, enabled in
            if !enabled {
                showPopover = false
            }
        }
    }

    private var button: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 8) {
                icon
                Text(usageText)
                    .kajiFont(size: 12, weight: .semibold, design: .monospaced)
                    .foregroundStyle(active ? KajiTheme.fg : KajiTheme.fgMuted)
            }
            .padding(.horizontal, 10)
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
        .kajiPointer()
        .help("AI Usage (\(KeyBindingStore.shared.combo(for: .toggleAIUsage).displayString))")
        .accessibilityLabel("AI Usage")
        .kajiPopover(isPresented: $showPopover, preferredEdge: .bottom) {
            AIUsagePanel(
                snapshots: service.snapshots,
                isRefreshing: service.isRefreshing,
                lastRefreshDate: service.lastRefreshDate,
                onRefresh: {
                    Task {
                        await service.refresh(force: true)
                    }
                }
            )
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let display = previewDisplay {
            ProviderIconView(
                iconName: display.iconName,
                size: 14,
                style: .monochrome(active ? KajiTheme.fg : KajiTheme.fgMuted)
            )
        } else {
            KajiIcon(systemName: "sparkles", size: 13)
                .foregroundStyle(active ? KajiTheme.fg : KajiTheme.fgMuted)
        }
    }

    private var previewDisplay: (percent: Int, iconName: String)? {
        guard let selection = service.previewSelection(pinnedRawValue: pinnedPreviewProviderID),
              case .available = selection.snapshot.state
        else { return nil }

        let snapshot = selection.snapshot
        let rowPercent = selection.row?.percent
        let usedPercent = max(0, min(100, rowPercent ?? snapshot.rows.compactMap(\.percent).max() ?? 0))
        let displayPercent: Double = switch usageDisplayMode {
        case .used:
            usedPercent
        case .remaining:
            max(0, min(100, 100 - usedPercent))
        }

        return (Int(displayPercent.rounded()), snapshot.providerIconName)
    }

    private var usageDisplayMode: AIUsageDisplayMode {
        AIUsageDisplayMode(rawValue: usageDisplayModeRaw) ?? AIUsageSettingsStore.defaultUsageDisplayMode
    }

    private var usageText: String {
        guard let previewDisplay else { return "--" }
        return "\(max(0, min(100, previewDisplay.percent)))%"
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
