import SwiftUI

struct EmptyProjectPlaceholder: View {
    let project: Project
    let onCreateTab: () -> Void
    @Environment(AppState.self) private var appState
    @State private var settings = CLILauncherSettings.shared

    private var enabledLaunchers: [CLILauncherConfiguration] {
        settings.enabledLaunchers.filter { $0.definition.id != "kajicode" }
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

                LauncherSquareButton(
                    iconName: "kaji",
                    accessibilityLabel: "KajiCode",
                    helpText: "Open KajiCode for this project",
                    iconSize: 18,
                    frameSize: 40
                ) {
                    runKajiCode()
                }
            }
            Text("No tabs in \(project.name)")
                .kajiFont(size: 14, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Text(descriptionText)
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Text("Terminal: \(KeyBindingStore.shared.combo(for: .newTab).displayString)")
                .kajiFont(size: 11, weight: .medium, design: .rounded)
                .foregroundStyle(KajiTheme.fgDim)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var descriptionText: String {
        enabledLaunchers.isEmpty
            ? "Open a terminal or KajiCode to start working in this project."
            : "Start with a terminal, KajiCode, or one of your enabled CLI tools."
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

    private func runKajiCode() {
        let command = KajiCodeLaunchCommand.split()
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        appState.createCommandTab(projectID: project.id, title: "KajiCode", command: command)
    }
}
