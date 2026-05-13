import SwiftUI

struct EditorSettingsView: View {
    @State private var settings = EditorSettings.shared
    @State private var typography = AppTypographySettings.shared
    @State private var monoFonts: [String] = []
    @State private var allowMarkdownRemoteImages = MarkdownPreviewPreferences.allowRemoteImages
    private let tabSizeOptions = [2, 4, 8]

    private var showsAppearanceSection: Bool { settings.defaultEditor == .builtIn }

    var body: some View {
        SettingsContainer {
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
                SettingsSection("Appearance") {
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

                SettingsSection("Code Editor", showsDivider: false) {
                    SettingsToggleRow(label: "Line Numbers", isOn: $settings.showsLineNumbers)
                    SettingsToggleRow(label: "Active Line", isOn: $settings.highlightsActiveLine)
                    SettingsToggleRow(label: "Indent Guides", isOn: $settings.showsIndentGuides)
                    SettingsToggleRow(label: "Render Whitespace", isOn: $settings.rendersWhitespace)
                    SettingsToggleRow(label: "Bracket Matching", isOn: $settings.highlightsMatchingBrackets)
                    SettingsToggleRow(label: "Word Wrap", isOn: $settings.wordWrapEnabled)
                    SettingsToggleRow(label: "Auto Close Pairs", isOn: $settings.autoClosesPairs)
                    SettingsToggleRow(label: "Auto Indent New Lines", isOn: $settings.autoIndentsNewLines)
                    SettingsRow("Tab Size") {
                        KajiSelect(
                            options: tabSizeOptions.map {
                                KajiSelectOption(id: String($0), title: String($0), value: $0)
                            },
                            selection: $settings.tabSize,
                            width: SettingsMetrics.controlWidth
                        )
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            monoFonts = AppTypographySettings.availableMonospacedFonts
        }
    }
}
