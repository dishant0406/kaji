import SwiftUI

struct EmptyProjectPlaceholder: View {
    let project: Project
    let onCreateTab: () -> Void
    @Environment(AppState.self) private var appState
    @State private var settings = CLILauncherSettings.shared

    private var enabledLaunchers: [CLILauncherConfiguration] {
        settings.enabledLaunchers
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            HStack(spacing: 10) {
                LauncherSquareButton(
                    iconName: "terminal",
                    accessibilityLabel: "Open Terminal",
                    helpText: "New terminal tab (\(KeyBindingStore.shared.combo(for: .newTab).displayString))",
                    iconSize: 18,
                    frameSize: 40,
                    action: onCreateTab
                )

                ForEach(enabledLaunchers) { launcher in
                    LauncherSquareButton(
                        iconName: launcher.definition.iconName,
                        accessibilityLabel: launcher.definition.displayName,
                        helpText: launcher.command,
                        iconSize: 18,
                        frameSize: 40
                    ) {
                        run(launcher)
                    }
                }
            }
            Text("No tabs in \(project.name)")
                .droidFont(size: 14, weight: .semibold)
                .foregroundStyle(DroidTheme.fg)
            Text(descriptionText)
                .droidFont(size: 12)
                .foregroundStyle(DroidTheme.fgMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Text("Terminal: \(KeyBindingStore.shared.combo(for: .newTab).displayString)")
                .droidFont(size: 11, weight: .medium, design: .rounded)
                .foregroundStyle(DroidTheme.fgDim)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var descriptionText: String {
        enabledLaunchers.isEmpty
            ? "Open a terminal to start working in this project."
            : "Start with a terminal or launch one of your enabled CLI tools."
    }

    private func run(_ launcher: CLILauncherConfiguration) {
        let command = launcher.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        appState.createCommandTab(
            projectID: project.id,
            title: launcher.definition.displayName,
            command: command
        )
    }
}
