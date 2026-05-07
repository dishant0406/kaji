import SwiftUI

struct CLILauncherRow: View {
    let launcher: CLILauncherConfiguration
    let provider: AIProviderIntegration?
    let isLast: Bool
    @Binding var isEnabled: Bool
    @Binding var command: String
    @State private var installState: CLILauncherInstallState
    @State private var installing = false
    @State private var installMessage: String?
    @State private var refreshed = false

    init(
        launcher: CLILauncherConfiguration,
        provider: AIProviderIntegration?,
        isLast: Bool,
        isEnabled: Binding<Bool>,
        command: Binding<String>
    ) {
        self.launcher = launcher
        self.provider = provider
        self.isLast = isLast
        _isEnabled = isEnabled
        _command = command
        _installState = State(initialValue: provider == nil ? .missing : .checking)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                CLILauncherIcon(iconName: launcher.definition.iconName, size: 16, color: DroidTheme.fg)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(launcher.definition.displayName)
                        .droidFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                        .foregroundStyle(DroidTheme.fg)
                    Text(statusText)
                        .droidFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(statusColor)
                }

                Spacer(minLength: 0)

                if installed, isEnabled, let provider {
                    Button {
                        AIProviderRegistry.shared.forceInstall(provider)
                        withAnimation { refreshed = true }
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation { refreshed = false }
                        }
                    } label: {
                        if refreshed {
                            Label {
                                Text("Done")
                            } icon: {
                                DroidIcon(systemName: "checkmark", size: 10)
                            }
                        } else {
                            Text("Refresh")
                        }
                    }
                    .buttonStyle(DroidButtonStyle(.secondary, size: .small))
                    .disabled(refreshed)
                }

                if !installed, provider != nil {
                    Button(installing ? "Installing" : "Install") {
                        installProvider()
                    }
                    .buttonStyle(DroidButtonStyle(.secondary, size: .small))
                    .disabled(installing || installState == .checking)
                }

                DroidSwitch(isOn: $isEnabled)
                    .disabled(!installed || installing)
            }
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            .padding(.top, SettingsMetrics.rowVerticalPadding + 2)
            .padding(.bottom, 6)

            HStack {
                DroidInput(
                    placeholder: launcher.definition.defaultCommand,
                    text: $command,
                    monospaced: true
                )
            }
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            .padding(.bottom, SettingsMetrics.rowVerticalPadding + 4)

            if !isLast {
                Divider().padding(.horizontal, SettingsMetrics.horizontalPadding)
            }
        }
        .task(id: launcher.id) {
            await refreshInstallState()
        }
    }

    private var installed: Bool {
        installState == .installed
    }

    private var statusText: String {
        if let installMessage { return installMessage }
        switch installState {
        case .checking:
            return "Checking CLI..."
        case .missing:
            return "CLI not installed"
        case .installed:
            return isEnabled ? "Enabled, installed" : "Disabled, installed"
        }
    }

    private var statusColor: Color {
        installState == .missing ? DroidTheme.diffRemoveFg : DroidTheme.fgMuted
    }

    private func refreshInstallState() async {
        guard provider != nil else {
            installState = .missing
            if isEnabled {
                isEnabled = false
            }
            return
        }
        installState = .checking
        let found = await CLILauncherInstallStateResolver.isInstalled(for: launcher.id)
        installState = found ? .installed : .missing
        if !found, isEnabled {
            isEnabled = false
        }
    }

    private func installProvider() {
        guard let provider, let command = AIProviderInstaller.command(for: provider) else {
            installMessage = "Install is not supported"
            return
        }
        installing = true
        installMessage = "Installing..."
        Task { @MainActor in
            let result = await AIProviderInstaller.install(command)
            let found = await CLILauncherInstallStateResolver.isInstalled(for: launcher.id)
            installState = found ? .installed : .missing
            installing = false
            switch result {
            case .success where found:
                isEnabled = true
                installMessage = "Installed"
            case .success:
                installMessage = "Install finished, but CLI was not found"
            case let .failure(error):
                isEnabled = false
                installMessage = error.localizedDescription
            }
        }
    }
}

private enum CLILauncherInstallState {
    case checking
    case installed
    case missing
}
