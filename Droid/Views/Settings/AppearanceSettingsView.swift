import SwiftUI

enum AppearanceSettingsKeys {
    static let sidebarTransparencyEnabled = "droid.appearance.sidebarTransparencyEnabled"
}

struct AppearanceSettingsView: View {
    @State private var themeService = ThemeService.shared
    @State private var showThemePicker = false
    @State private var currentTheme: String?
    @AppStorage("droid.vcsDisplayMode") private var vcsDisplayMode = VCSDisplayMode.attached.rawValue
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
                                .font(.system(size: SettingsMetrics.labelFontSize))
                                .lineLimit(1)
                            DroidIcon(systemName: "chevron.up.chevron.down", size: 10)
                        }
                    }
                    .buttonStyle(DroidButtonStyle(.secondary, size: .regular))
                    .droidPopover(isPresented: $showThemePicker, preferredEdge: .bottom) {
                        ThemePicker()
                            .environment(themeService)
                    }
                }
            }

            SettingsSection("Source Control", showsDivider: false) {
                SettingsRow("Display Mode") {
                    SegmentedPicker(
                        selection: $vcsDisplayMode,
                        options: VCSDisplayMode.allCases.map { ($0.rawValue, $0.title) }
                    )
                    .frame(width: SettingsMetrics.controlWidth)
                }
            }
        }
        .task {
            currentTheme = themeService.currentThemeName()
        }
        .onReceive(NotificationCenter.default.publisher(for: .themeDidChange)) { _ in
            currentTheme = themeService.currentThemeName()
        }
    }
}
