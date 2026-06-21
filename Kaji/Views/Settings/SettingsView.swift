import SwiftUI

struct SettingsView: View {
    var onClose: (() -> Void)?
    @State private var selection = SettingsPane.general
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(KajiTheme.border)
                .frame(height: 1)
            HStack(spacing: 0) {
                sidebar
                Rectangle()
                    .fill(KajiTheme.border)
                    .frame(width: 1)
                content
            }
        }
        .kajiGlassEffectScope(spacing: 8)
        .frame(width: 860, height: 560)
        .background(
            TranslucentSurface(
                base: KajiTheme.bg,
                material: .underWindowBackground,
                tintOpacity: 0.24,
                glassCornerRadius: KajiShape.modalRadius
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: KajiShape.modalRadius))
        .overlay(
            RoundedRectangle(cornerRadius: KajiShape.modalRadius)
                .stroke(KajiTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
        .onReceive(NotificationCenter.default.publisher(for: .openParentAgentSettings)) { _ in
            selection = .agents
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Settings")
                .kajiFont(size: 13, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Spacer()
            if let onClose {
                IconButton(symbol: "xmark", accessibilityLabel: "Close Settings") {
                    onClose()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            KajiTheme.chrome.opacity(0.42)
        )
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsPane.allCases) { pane in
                SettingsSidebarButton(
                    title: pane.rawValue,
                    icon: pane.icon,
                    isSelected: selection == pane
                ) {
                    select(pane)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 190, alignment: .topLeading)
        .background(
            TranslucentSurface(
                base: KajiTheme.secondaryBackground,
                material: .sidebar,
                tintOpacity: 0.18,
                glassCornerRadius: KajiShape.modalRadius
            )
        )
    }

    private var content: some View {
        Group {
            switch selection {
            case .general:
                GeneralSettingsView()
            case .appearance:
                AppearanceSettingsView()
            case .terminal:
                TerminalSettingsView()
            case .cli:
                CLILauncherSettingsView()
            case .extensions:
                ExtensionsSettingsView()
            case .agents:
                AgentSettingsView()
            case .editor:
                EditorSettingsView()
            case .shortcuts:
                KeyboardShortcutsSettingsView()
            case .notifications:
                NotificationSettingsView()
            case .aiUsage:
                AIUsageSettingsView()
            }
        }
        .id(selection)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .transition(KajiMotion.paneTransition(reduceMotion: reduceMotion))
        .animation(KajiMotion.preferred(KajiMotion.panel, reduceMotion: reduceMotion), value: selection)
        .background(
            TranslucentSurface(
                base: KajiTheme.bg,
                material: .underWindowBackground,
                tintOpacity: 0.28,
                glassCornerRadius: KajiShape.modalRadius
            )
        )
    }

    private func select(_ pane: SettingsPane) {
        withAnimation(KajiMotion.preferred(KajiMotion.panel, reduceMotion: reduceMotion)) {
            selection = pane
        }
    }
}
