import SwiftUI

struct KasetMusicSettingsRow: View {
    @Binding var isEnabled: Bool
    @Binding var showsFooterIcon: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                KajiIcon(systemName: "music.note", size: 16)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Kaset")
                        .kajiFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                        .foregroundStyle(KajiTheme.fg)
                    Text(statusText)
                        .kajiFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(KajiTheme.fgMuted)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                KajiSwitch(isOn: $isEnabled)
            }
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            .padding(.vertical, SettingsMetrics.rowVerticalPadding + 4)

            if isEnabled {
                SettingsDetailToggleRow(
                    label: "Show footer icon",
                    detail: "Display the global Kaset control in the sidebar footer.",
                    isOn: $showsFooterIcon
                )
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button("Open Kaset") {
                        NotificationCenter.default.post(name: .openKasetMusicPanel, object: nil)
                    }
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                }
                .padding(.horizontal, SettingsMetrics.horizontalPadding)
                .padding(.bottom, SettingsMetrics.rowVerticalPadding + 4)
            }
        }
    }

    private var statusText: String {
        isEnabled ? "Enabled using the Kaset package" : "Disabled, music UI hidden"
    }
}
