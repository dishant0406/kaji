import SwiftUI

enum AppearanceSettingsKeys {
    static let sidebarTransparencyEnabled = "kaji.appearance.sidebarTransparencyEnabled"
    static let interfaceTransparencyAmount = "kaji.appearance.interfaceTransparencyAmount"
}

struct AppearanceSettingsView: View {
    @State private var themeService = ThemeService.shared
    @State private var showThemePicker = false
    @State private var currentTheme: String?
    @AppStorage(AppearanceSettingsKeys.sidebarTransparencyEnabled) private var sidebarTransparencyEnabled = false
    @AppStorage(AppearanceSettingsKeys.interfaceTransparencyAmount) private var interfaceTransparencyAmount = 0.7

    var body: some View {
        SettingsContainer {
            SettingsSection(
                "Interface",
                footer: "Applies native material-backed transparency to window chrome, popovers, and modal surfaces."
            ) {
                SettingsToggleRow(
                    label: "Interface transparency",
                    isOn: $sidebarTransparencyEnabled
                )
                SettingsSliderRow(
                    label: "Amount",
                    value: $interfaceTransparencyAmount,
                    range: 0 ... 1,
                    isEnabled: sidebarTransparencyEnabled,
                    valueText: { value in
                        "\(Int((value * 100).rounded()))%"
                    }
                )
            }

            SettingsSection("Terminal") {
                SettingsRow("Theme") {
                    Button {
                        showThemePicker.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Text(currentTheme ?? "Default")
                                .kajiFont(size: SettingsMetrics.labelFontSize)
                                .lineLimit(1)
                            KajiIcon(systemName: "chevron.up.chevron.down", size: 10)
                        }
                    }
                    .buttonStyle(KajiButtonStyle(.secondary, size: .regular))
                    .kajiPopover(isPresented: $showThemePicker, preferredEdge: .bottom) {
                        ThemePicker(
                            onRequestCreate: {
                                showThemePicker = false
                                NotificationCenter.default.post(name: .requestCreateThemeModal, object: nil)
                            },
                            onDismiss: { showThemePicker = false }
                        )
                        .environment(themeService)
                    }
                }
            }
        }
        .task {
            currentTheme = themeService.currentThemeDisplayName()
        }
        .onReceive(NotificationCenter.default.publisher(for: .themeDidChange)) { _ in
            currentTheme = themeService.currentThemeDisplayName()
        }
        .onChange(of: interfaceTransparencyAmount) { _, newValue in
            interfaceTransparencyAmount = min(max(newValue, 0), 1)
        }
    }
}
