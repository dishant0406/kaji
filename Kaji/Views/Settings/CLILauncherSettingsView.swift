import SwiftUI

struct CLILauncherSettingsView: View {
    @State private var settings = CLILauncherSettings.shared

    var body: some View {
        ScrollView {
            SettingsContainer {
                KajiCodeSetupView()

                SettingsSection(
                    "Coding Agents",
                    footer: "Enabled agents appear in the workspace footer and are available to the parent agent. "
                        + "Kaji also installs notification hooks for enabled agents.",
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
