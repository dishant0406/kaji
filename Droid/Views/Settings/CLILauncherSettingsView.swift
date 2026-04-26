import SwiftUI

struct CLILauncherSettingsView: View {
    @State private var settings = CLILauncherSettings.shared

    var body: some View {
        ScrollView {
            SettingsContainer {
                SettingsSection(
                    "CLI Launchers",
                    footer: "Enabled launchers appear in the active project workspace footer. Clicking one opens a terminal tab and runs its command.",
                    showsDivider: false
                ) {
                    ForEach(Array(settings.launchers.enumerated()), id: \.element.id) { index, launcher in
                        CLILauncherRow(
                            launcher: launcher,
                            isLast: index == settings.launchers.count - 1,
                            isEnabled: binding(for: launcher.id, keyPath: \.isEnabled),
                            command: binding(for: launcher.id, keyPath: \.command)
                        )
                    }
                }
            }
        }
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
    let isLast: Bool
    @Binding var isEnabled: Bool
    @Binding var command: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                CLILauncherIcon(iconName: launcher.definition.iconName, size: 16, color: DroidTheme.fg)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(launcher.definition.displayName)
                        .font(.system(size: SettingsMetrics.labelFontSize, weight: .medium))
                        .foregroundStyle(DroidTheme.fg)
                    Text("Default: \(launcher.definition.defaultCommand)")
                        .font(.system(size: SettingsMetrics.footnoteFontSize))
                        .foregroundStyle(DroidTheme.fgMuted)
                }

                Spacer(minLength: 0)

                DroidSwitch(isOn: $isEnabled)
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
    }
}
