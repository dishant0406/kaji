import SwiftUI

struct CLILauncherSettingsView: View {
    @State private var settings = CLILauncherSettings.shared

    var body: some View {
        ScrollView {
            SettingsContainer {
                SettingsSection(
                    "Coding Agents",
                    footer: "Enabled agents appear in the workspace footer and are available to the parent agent. "
                        + "Droid also installs notification hooks for enabled agents.",
                    showsDivider: false
                ) {
                    ForEach(Array(settings.launchers.enumerated()), id: \.element.id) { index, launcher in
                        CLILauncherRow(
                            launcher: launcher,
                            provider: provider(for: launcher.id),
                            isLast: index == settings.launchers.count - 1,
                            isEnabled: binding(for: launcher.id, keyPath: \.isEnabled),
                            command: binding(for: launcher.id, keyPath: \.command)
                        )
                    }
                }
            }
        }
    }

    private func provider(for id: String) -> AIProviderIntegration? {
        AIProviderRegistry.shared.providers.first { $0.id == id }
    }

    private func binding<Value>(
        for id: String,
        keyPath: KeyPath<CLILauncherConfiguration, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                settings.launchers.first(where: { $0.id == id })?[keyPath: keyPath]
                    ?? settings.launchers[0][keyPath: keyPath]
            },
            set: { newValue in
                if keyPath == \CLILauncherConfiguration.isEnabled,
                   let enabled = newValue as? Bool
                {
                    settings.setEnabled(enabled, for: id)
                } else if keyPath == \CLILauncherConfiguration.command,
                          let command = newValue as? String
                {
                    settings.setCommand(command, for: id)
                }
            }
        )
    }
}

private struct CLILauncherRow: View {
    let launcher: CLILauncherConfiguration
    let provider: AIProviderIntegration?
    let isLast: Bool
    @Binding var isEnabled: Bool
    @Binding var command: String
    @State private var installed: Bool
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
        _installed = State(initialValue: provider?.isToolInstalled() ?? false)
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
                        .foregroundStyle(installed ? DroidTheme.fgMuted : DroidTheme.diffRemoveFg)
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
                    .disabled(installing)
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
        .onAppear(perform: refreshInstallState)
    }

    private var statusText: String {
        if let installMessage { return installMessage }
        guard installed else { return "CLI not installed" }
        return isEnabled ? "Enabled, installed" : "Disabled, installed"
    }

    private func refreshInstallState() {
        installed = provider?.isToolInstalled() ?? false
        if !installed {
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
            installed = provider.isToolInstalled()
            installing = false
            switch result {
            case .success where installed:
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
