import SwiftUI

enum AppearanceSettingsKeys {
    static let sidebarTransparencyEnabled = "droid.appearance.sidebarTransparencyEnabled"
}

struct AppearanceSettingsView: View {
    @State private var themeService = ThemeService.shared
    @State private var showThemePicker = false
    @State private var currentTheme: String?
    @AppStorage(AppearanceSettingsKeys.sidebarTransparencyEnabled) private var sidebarTransparencyEnabled = false

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
            }

            SettingsSection("Terminal") {
                SettingsRow("Theme") {
                    Button {
                        showThemePicker.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Text(currentTheme ?? "Default")
                                .droidFont(size: SettingsMetrics.labelFontSize)
                                .lineLimit(1)
                            DroidIcon(systemName: "chevron.up.chevron.down", size: 10)
                        }
                    }
                    .buttonStyle(DroidButtonStyle(.secondary, size: .regular))
                    .droidPopover(isPresented: $showThemePicker, preferredEdge: .bottom) {
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
    }
}
