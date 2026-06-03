import SwiftUI

enum AppearanceSettingsKeys {
    static let interfaceMode = "kaji.appearance.interfaceMode"
    static let sidebarTransparencyEnabled = "kaji.appearance.sidebarTransparencyEnabled"
    static let interfaceTransparencyAmount = "kaji.appearance.interfaceTransparencyAmount"
}

struct AppearanceSettingsView: View {
    @State private var themeService = ThemeService.shared
    @State private var showThemePicker = false
    @State private var currentTheme: String?
    @AppStorage(AppearanceSettingsKeys.interfaceMode) private var interfaceModeRaw = ""
    @AppStorage(AppearanceSettingsKeys.sidebarTransparencyEnabled) private var sidebarTransparencyEnabled = false
    @AppStorage(AppearanceSettingsKeys.interfaceTransparencyAmount) private var interfaceTransparencyAmount = 0.7
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        SettingsContainer {
            SettingsSection(
                "Interface",
                footer: interfaceFooter
            ) {
                picker(
                    "Style",
                    selection: Binding(
                        get: { requestedMode.rawValue },
                        set: { rawValue in
                            interfaceModeRaw = rawValue
                            sidebarTransparencyEnabled = rawValue != AppearanceMode.solid.rawValue
                        }
                    ),
                    options: availableModes.map(\.rawValue)
                )
                SettingsSliderRow(
                    label: "Amount",
                    value: $interfaceTransparencyAmount,
                    range: 0 ... 1,
                    isEnabled: requestedMode != .solid && !reduceTransparency,
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

    private var availableModes: [AppearanceMode] {
        AppearanceMode.allCases
    }

    private var requestedMode: AppearanceMode {
        AppearanceMode(rawValue: interfaceModeRaw) ?? AppearanceModeResolver.requestedMode(
            modeRaw: interfaceModeRaw,
            legacyTransparencyEnabled: sidebarTransparencyEnabled
        )
    }

    private var interfaceFooter: String {
        if reduceTransparency {
            return "Reduce Transparency is enabled in macOS Accessibility settings, so Kaji is using solid interface surfaces."
        }
        if AppearanceCapabilities.supportsLiquidGlass {
            return "Glass uses native macOS Liquid Glass for Kaji chrome, popovers, and floating panels."
        }
        return "Applies material-backed transparency. Glass is available on macOS 26 and later."
    }

    private func picker(_ label: String, selection: Binding<String>, options: [String]) -> some View {
        SettingsRow(label) {
            KajiSelect(
                options: options.map { KajiSelectOption(id: $0, title: $0, value: $0) },
                selection: selection,
                width: SettingsMetrics.controlWidth
            )
        }
    }
}
