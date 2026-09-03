import SwiftUI

struct KajiCLICommandSettingsSection: View {
    @State private var installState = KajiCLICommandInstaller.state()
    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        SettingsSection(
            "Command Line",
            footer: "Install a shell command so kaji . or kaji ~/path opens that folder in Kaji."
        ) {
            HStack(alignment: .center, spacing: 10) {
                KajiIcon(systemName: "terminal", size: 16)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text("kaji command")
                        .kajiFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                        .foregroundStyle(KajiTheme.fg)
                    Text(statusText)
                        .kajiFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(statusColor)
                        .lineLimit(2)
                    Text("Examples: kaji .  ·  kaji ~/code/project")
                        .kajiFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(KajiTheme.fgDim)
                        .lineLimit(1)
                    if let message {
                        Text(message)
                            .kajiFont(size: SettingsMetrics.footnoteFontSize)
                            .foregroundStyle(KajiTheme.fgMuted)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    if case .installed = installState {
                        Button("Uninstall", action: uninstall)
                            .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                            .disabled(isWorking)
                    }
                    Button(primaryButtonTitle, action: install)
                        .buttonStyle(KajiButtonStyle(.primary, size: .small))
                        .disabled(isWorking)
                }
            }
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            .padding(.vertical, SettingsMetrics.rowVerticalPadding + 4)
            .onAppear(perform: refresh)
        }
    }

    private var statusText: String {
        if isWorking {
            return "Updating command..."
        }
        switch installState {
        case .installed:
            return "Installed at /usr/local/bin/kaji"
        case .missing:
            return "Not installed"
        case let .needsRepair(message):
            return message
        }
    }

    private var statusColor: Color {
        switch installState {
        case .installed:
            KajiTheme.fgMuted
        case .missing:
            KajiTheme.fgDim
        case .needsRepair:
            KajiTheme.diffRemoveFg
        }
    }

    private var primaryButtonTitle: String {
        if isWorking {
            return "Working"
        }
        switch installState {
        case .installed:
            return "Reinstall"
        case .missing:
            return "Install"
        case .needsRepair:
            return "Repair"
        }
    }

    private func refresh() {
        installState = KajiCLICommandInstaller.state()
    }

    private func install() {
        run { KajiCLICommandInstaller.install() }
    }

    private func uninstall() {
        run { KajiCLICommandInstaller.uninstall() }
    }

    private func run(_ operation: @escaping @Sendable () -> KajiCLICommandInstallResult) {
        isWorking = true
        message = nil
        Task.detached {
            let result = operation()
            await MainActor.run {
                installState = result.state
                message = result.message
                isWorking = false
            }
        }
    }
}
