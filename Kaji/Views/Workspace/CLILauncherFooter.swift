import SwiftUI

struct CLILauncherFooter: View {
    let projectID: UUID
    let worktreeKey: WorktreeKey?
    let worktreePath: String?
    var terminalExpanded = false
    var onToggleTerminal: (() -> Void)?
    var onOpenMCPControlPanel: (() -> Void)?
    @Environment(AppState.self) private var appState
    @State private var settings = CLILauncherSettings.shared
    @State private var showsShortcuts = false
    @AppStorage(BrowserExtensionPreferences.enabledKey) private var browserEnabled = false

    private var enabledLaunchers: [CLILauncherConfiguration] {
        settings.enabledLaunchers
    }

    var body: some View {
        HStack(spacing: 8) {
            LauncherSquareButton(
                iconName: "kaji",
                accessibilityLabel: "Kaji Agent",
                helpText: "Open Kaji Agent split"
            ) {
                appState.createParentAgentSplit(projectID: projectID)
            }
            .attachedShortcutHint(for: .openKajiAgentSplit)
            ForEach(Array(enabledLaunchers.enumerated()), id: \.element.id) { index, launcher in
                LauncherSquareButton(
                    iconName: launcher.definition.iconName,
                    accessibilityLabel: launcher.definition.displayName,
                    helpText: launcher.command
                ) {
                    run(launcher)
                }
                .modifier(FooterLauncherShortcutHintModifier(index: index))
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                KajiCodeGraphFooterControl(
                    projectID: projectID,
                    worktreeKey: worktreeKey,
                    worktreePath: worktreePath
                )

                SpeechInputFooterControl()

                if browserEnabled {
                    IconButton(symbol: "globe", accessibilityLabel: "Browser") {
                        NotificationCenter.default.post(name: .toggleBrowserPanel, object: projectID)
                    }
                    .help("Browser")
                    .attachedShortcutHint(for: .toggleBrowserPanel)
                }

                IconButton(symbol: "mcp", accessibilityLabel: "MCP Servers") {
                    onOpenMCPControlPanel?()
                }
                .help("MCP Servers")
                .attachedShortcutHint(for: .toggleMCPControlPanel)

                IconButton(symbol: "keyboard", selected: showsShortcuts, accessibilityLabel: "Shortcuts") {
                    showsShortcuts.toggle()
                }
                .help("Shortcuts")
                .kajiPopover(isPresented: $showsShortcuts, preferredEdge: .top) {
                    ShortcutReferencePopover()
                }

                IconButton(symbol: "square.split.2x1", accessibilityLabel: "Split Right") {
                    appState.splitFocusedArea(direction: .horizontal, projectID: projectID)
                }
                .help(shortcutTooltip("Split Right", for: .splitRight))
                .attachedShortcutHint(for: .splitRight)

                IconButton(symbol: "square.split.1x2", accessibilityLabel: "Split Down") {
                    appState.splitFocusedArea(direction: .vertical, projectID: projectID)
                }
                .help(shortcutTooltip("Split Down", for: .splitDown))
                .attachedShortcutHint(for: .splitDown)

                if let onToggleTerminal {
                    IconButton(
                        symbol: terminalExpanded ? "chevron.down" : "chevron.up",
                        selected: terminalExpanded,
                        accessibilityLabel: terminalExpanded ? "Hide Footer Terminal" : "Show Footer Terminal"
                    ) {
                        onToggleTerminal()
                    }
                    .help(terminalExpanded ? "Hide Footer Terminal" : "Show Footer Terminal")
                    .attachedShortcutHint(for: .toggleFooterTerminal)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: KajiLayout.footerBarHeight)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(KajiTheme.border)
                .frame(height: 1)
        }
        .background(KajiTheme.secondaryBackground)
    }

    private func run(_ launcher: CLILauncherConfiguration) {
        let command = launcher.command.trimmingCharacters(in: .whitespacesAndNewlines)
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

private struct FooterLauncherShortcutHintModifier: ViewModifier {
    let index: Int

    func body(content: Content) -> some View {
        if let action = action(for: index) {
            content.attachedShortcutHint(for: action)
        } else {
            content
        }
    }

    private func action(for index: Int) -> ShortcutAction? {
        switch index {
        case 0: .openFooterLauncher1
        case 1: .openFooterLauncher2
        case 2: .openFooterLauncher3
        case 3: .openFooterLauncher4
        case 4: .openFooterLauncher5
        default: nil
        }
    }
}
