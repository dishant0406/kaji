import SwiftUI

struct BrowserExtensionRow: View {
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            DroidIcon(systemName: "globe", size: 16)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("Droid Browser")
                    .droidFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                    .foregroundStyle(DroidTheme.fg)
                Text(statusText)
                    .droidFont(size: SettingsMetrics.footnoteFontSize)
                    .foregroundStyle(DroidTheme.fgMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            DroidSwitch(isOn: $isEnabled)
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding + 4)
    }

    private var statusText: String {
        isEnabled ? "Enabled for side panel and coding agents" : "Disabled, browser UI and agent tools hidden"
    }
}

struct BrowserUnsafeToolsRow: View {
    @Binding var isEnabled: Bool
    let isBrowserEnabled: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            DroidIcon(systemName: "exclamationmark.shield", size: 16)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("Unsafe Browser Tools")
                    .droidFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                    .foregroundStyle(DroidTheme.fg)
                Text(statusText)
                    .droidFont(size: SettingsMetrics.footnoteFontSize)
                    .foregroundStyle(DroidTheme.fgMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            DroidSwitch(isOn: $isEnabled)
                .disabled(!isBrowserEnabled)
        }
        .opacity(isBrowserEnabled ? 1 : 0.55)
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding + 4)
    }

    private var statusText: String {
        if !isBrowserEnabled { return "Enable Droid Browser before allowing unsafe tools" }
        return isEnabled ? "Allows file upload, drag-drop, and unsafe code tools" : "Blocked for safer browser automation"
    }
}
