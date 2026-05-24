import SwiftUI

struct CommitMessageSettingsSection: View {
    @Bindable var settings: GitCommitMessageSettingsStore

    var body: some View {
        SettingsSection(
            "Commit Messages",
            footer: "Controls commit-message detail and how much context Kaji sends while refining generated messages."
        ) {
            SettingsRow("Detail") {
                VStack(alignment: .leading, spacing: 5) {
                    KajiSelect(
                        options: contextOptions,
                        selection: contextSelection,
                        width: 320
                    )
                    Text(settings.selectedContextLevel.detail)
                        .kajiFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(KajiTheme.fgDim)
                }
                .frame(width: 320, alignment: .leading)
            }

            SettingsRow("Instructions") {
                KajiTextArea(
                    placeholder: "Prefer conventional commits. Mention product area. Add a body only for risky changes.",
                    text: instructions,
                    minHeight: 92,
                    maxHeight: 130,
                    monospaced: false
                )
                .frame(width: 320)
            }
        }
    }

    private var contextOptions: [KajiSelectOption<String>] {
        GitCommitMessageContextLevel.allCases.map {
            KajiSelectOption(id: $0.rawValue, title: $0.title, value: $0.rawValue)
        }
    }

    private var contextSelection: Binding<String> {
        Binding(
            get: { settings.contextLevel },
            set: { settings.contextLevel = $0 }
        )
    }

    private var instructions: Binding<String> {
        Binding(
            get: { settings.customInstructions },
            set: { settings.customInstructions = $0 }
        )
    }
}
