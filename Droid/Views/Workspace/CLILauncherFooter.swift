import SwiftUI

struct CLILauncherFooter: View {
    let projectID: UUID
    @Environment(AppState.self) private var appState
    @State private var settings = CLILauncherSettings.shared

    private var enabledLaunchers: [CLILauncherConfiguration] {
        settings.enabledLaunchers
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(enabledLaunchers) { launcher in
                LauncherSquareButton(
                    iconName: launcher.definition.iconName,
                    accessibilityLabel: launcher.definition.displayName,
                    helpText: launcher.command
                ) {
                    run(launcher)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                IconButton(symbol: "square.split.2x1", accessibilityLabel: "Split Right") {
                    appState.splitFocusedArea(direction: .horizontal, projectID: projectID)
                }
                .help(shortcutTooltip("Split Right", for: .splitRight))

                IconButton(symbol: "square.split.1x2", accessibilityLabel: "Split Down") {
                    appState.splitFocusedArea(direction: .vertical, projectID: projectID)
                }
                .help(shortcutTooltip("Split Down", for: .splitDown))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: DroidLayout.footerBarHeight)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DroidTheme.border)
                .frame(height: 1)
        }
        .background(DroidTheme.secondaryBackground)
    }

    private func run(_ launcher: CLILauncherConfiguration) {
        let command = CLILaunchCommandResolver.resolve(launcher)
        guard !command.isEmpty else { return }
        appState.createCommandSplit(
            projectID: projectID,
            title: launcher.definition.displayName,
            command: command
        )
    }

    private func shortcutTooltip(_ name: String, for action: ShortcutAction) -> String {
        "\(name) (\(KeyBindingStore.shared.combo(for: action).displayString))"
    }
}
