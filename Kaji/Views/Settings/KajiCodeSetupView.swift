import SwiftUI

struct KajiCodeSetupView: View {
    @State private var state = KajiCodeInstaller.state()
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        SettingsSection(
            "KajiCode",
            footer: "Kaji installs the latest compatible KajiCode release into Application Support "
                + "and launches it from the workspace footer.",
            showsDivider: true
        ) {
            HStack(alignment: .center, spacing: 10) {
                CLILauncherIcon(iconName: "kaji", size: 16, color: KajiTheme.fg)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Managed CLI")
                        .kajiFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                        .foregroundStyle(KajiTheme.fg)
                    Text(statusText)
                        .kajiFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(statusColor)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if case .installed = state {
                    Button("Uninstall", action: uninstall)
                        .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                        .disabled(isWorking)
                }

                Button(primaryTitle, action: install)
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    .disabled(isWorking)
            }
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            .padding(.vertical, SettingsMetrics.rowVerticalPadding + 2)
        }
    }

    private var primaryTitle: String {
        if isWorking { return "Installing" }
        if case .installed = state { return "Update" }
        return "Install"
    }

    private var statusText: String {
        if let message { return message }
        switch state {
        case .missing:
            if KajiCodeRuntimeLocator.resolve()?.source == .developerOverride { return "Using developer override" }
            return "Not installed"
        case let .installed(manifest):
            return "Installed \(manifest.activeVersion) from \(manifest.platform)"
        case let .needsRepair(detail):
            return detail
        }
    }

    private var statusColor: Color {
        switch state {
        case .installed:
            KajiTheme.fgMuted
        case .missing,
             .needsRepair:
            KajiTheme.diffRemoveFg
        }
    }

    private func install() {
        isWorking = true
        message = "Installing..."
        Task { @MainActor in
            let result = await KajiCodeInstaller.installLatest()
            state = result.state
            message = result.message
            isWorking = false
        }
    }

    private func uninstall() {
        let result = KajiCodeInstaller.uninstall()
        state = result.state
        message = result.message
    }
}
