import SwiftUI

struct EditorSettingsView: View {
    @State private var settings = EditorSettings.shared
    @State private var typography = AppTypographySettings.shared
    @State private var monoFonts: [String] = []
    @State private var allowMarkdownRemoteImages = MarkdownPreviewPreferences.allowRemoteImages

    private var showsAppearanceSection: Bool { settings.defaultEditor == .builtIn }

    var body: some View {
        VStack(spacing: 0) {
            SettingsSection("Editor") {
                SettingsRow("Default Editor") {
                    KajiSelect(
                        options: EditorSettings.DefaultEditor.allCases.map {
                            KajiSelectOption(id: $0.rawValue, title: $0.displayName, value: $0)
                        },
                        selection: $settings.defaultEditor,
                        width: SettingsMetrics.controlWidth
                    )
                }

                if settings.defaultEditor == .terminalCommand {
                    SettingsInputRow(
                        label: "Editor Command",
                        placeholder: "vim",
                        text: $settings.externalEditorCommand,
                        monospaced: true
                    )
                }
            }

            SettingsSection(
                "Markdown Preview",
                footer: "Remote images are fetched over HTTPS only. Plain HTTP and other schemes are blocked.",
                showsDivider: showsAppearanceSection
            ) {
                SettingsToggleRow(label: "Allow Remote Images", isOn: $allowMarkdownRemoteImages)
                    .onChange(of: allowMarkdownRemoteImages) { _, newValue in
                        MarkdownPreviewPreferences.allowRemoteImages = newValue
                    }
            }

            if showsAppearanceSection {
                SettingsSection("Appearance", showsDivider: false) {
                    SettingsRow("Font Family") {
                        KajiSelect(
                            options: monoFonts.map {
                                KajiSelectOption(id: $0, title: $0, value: $0)
                            },
                            selection: $typography.fontFamily,
                            width: SettingsMetrics.controlWidth
                        )
                    }

                    SettingsRow("Base Font Size") {
                        HStack(spacing: 8) {
                            Button {
                                guard typography.fontSize > 10 else { return }
                                typography.fontSize -= 1
                            } label: {
                                KajiIcon(systemName: "minus", size: 10)
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(KajiButtonStyle(.secondary, size: .small))

                            Text("\(Int(typography.fontSize)) pt")
                                .kajiFont(size: SettingsMetrics.labelFontSize, design: .monospaced)
                                .foregroundStyle(KajiTheme.fg)
                                .frame(width: 44)

                            Button {
                                guard typography.fontSize < 36 else { return }
                                typography.fontSize += 1
                            } label: {
                                KajiIcon(systemName: "plus", size: 10)
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                    typography.resetToDefaults()
                }
                .buttonStyle(KajiButtonStyle(.ghost, size: .small))
            }
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            .padding(.bottom, SettingsMetrics.verticalPadding)
        }
        .task {
            monoFonts = AppTypographySettings.availableMonospacedFonts
        }
    }
}
