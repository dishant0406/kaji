import Kaset
import SwiftUI

struct CLILauncherFooter: View {
    let projectID: UUID
    let worktreeKey: WorktreeKey?
    let worktreePath: String?
    let kasetMusicController: KasetEmbeddedController?
    var terminalExpanded = false
    var onToggleTerminal: (() -> Void)?
    var onOpenMCPControlPanel: (() -> Void)?
    @Environment(AppState.self) private var appState
    @State private var settings = CLILauncherSettings.shared
    @State private var showsShortcuts = false
    @AppStorage(BrowserExtensionPreferences.enabledKey) private var browserEnabled = false
    @AppStorage(KasetMusicPreferences.enabledKey) private var kasetMusicEnabled = false

    private var enabledLaunchers: [CLILauncherConfiguration] {
        settings.footerLaunchers
    }

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                LauncherSquareButton(
                    iconName: "kaji",
                    accessibilityLabel: "KajiCode",
                    helpText: "Open KajiCode split"
                ) {
                    runKajiCode()
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

                    MeetingNotesFooterControl {
                        NotificationCenter.default.post(name: .toggleMeetingNotesPanel, object: nil)
                    }

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

            GeometryReader { proxy in
                if shouldShowKasetNowPlaying(width: proxy.size.width), let kasetMusicController {
                    KasetNowPlayingFooterControl(controller: kasetMusicController)
                        .frame(width: min(520, max(300, proxy.size.width * 0.36)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .allowsHitTesting(shouldShowKasetNowPlaying(width: nil))
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
        let command = CLILauncherCommandResolver.resolve(launcher.command).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        appState.createCommandSplit(
            projectID: projectID,
            title: launcher.definition.displayName,
            command: command
        )
    }

    private func runKajiCode() {
        let saved = settings.command(for: "kajicode").trimmingCharacters(in: .whitespacesAndNewlines)
        let base = saved.isEmpty ? KajiCodeCommandBuilder.splitCommand() : CLILauncherCommandResolver.resolve(saved)
        let command = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        appState.createCommandSplit(projectID: projectID, title: "KajiCode", command: command)
    }

    private func shortcutTooltip(_ name: String, for action: ShortcutAction) -> String {
        "\(name) (\(KeyBindingStore.shared.combo(for: action).displayString))"
    }

    private func shouldShowKasetNowPlaying(width: CGFloat?) -> Bool {
        guard kasetMusicEnabled, let kasetMusicController else { return false }
        guard kasetMusicController.nowPlaying.hasActiveItem else { return false }
        guard let width else { return true }
        return width >= 720
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
