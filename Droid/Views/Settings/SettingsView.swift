import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case cli = "CLI"
    case agents = "Agents"
    case editor = "Editor"
    case shortcuts = "Shortcuts"
    case notifications = "Notifications"
    case aiUsage = "AI Usage"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .cli: "terminal"
        case .agents: "rectangle.stack"
        case .editor: "pencil.line"
        case .shortcuts: "keyboard"
        case .notifications: "bell"
        case .aiUsage: "chart.bar"
        }
    }
}

struct SettingsView: View {
    var onClose: (() -> Void)?
    @State private var selection = SettingsPane.general

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(DroidTheme.border)
                .frame(height: 1)
            HStack(spacing: 0) {
                sidebar
                Rectangle()
                    .fill(DroidTheme.border)
                    .frame(width: 1)
                content
            }
        }
        .frame(width: 860, height: 560)
        .background(
            TranslucentSurface(
                base: DroidTheme.tertiaryBackground,
                material: .hudWindow,
                tintOpacity: 0.66,
                gradientOpacity: 0.08
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: DroidShape.modalRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DroidShape.modalRadius)
                .stroke(DroidTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Settings")
                .droidFont(size: 13, weight: .semibold)
                .foregroundStyle(DroidTheme.fg)
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
            DroidTheme.chrome.opacity(0.42)
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
                    selection = pane
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 190, alignment: .topLeading)
        .background(
            DroidTheme.secondaryBackground.opacity(0.42)
        )
    }

    private var content: some View {
        Group {
            switch selection {
            case .general:
                GeneralSettingsView()
            case .appearance:
                AppearanceSettingsView()
            case .cli:
                CLILauncherSettingsView()
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            DroidTheme.bg.opacity(0.34)
        )
    }
}

private struct SettingsSidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                DroidIcon(systemName: icon, size: 12)
                    .frame(width: 14)
                Text(title)
                    .droidFont(size: 12, weight: .medium)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? DroidTheme.fg : (hovered ? DroidTheme.fg : DroidTheme.fgMuted))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                    .stroke(rowBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return DroidTheme.tertiaryBackground }
        if hovered { return DroidTheme.hover }
        return .clear
    }

    private var rowBorder: Color {
        if isSelected { return DroidTheme.borderStrong }
        if hovered { return DroidTheme.border.opacity(0.7) }
        return .clear
    }
}
