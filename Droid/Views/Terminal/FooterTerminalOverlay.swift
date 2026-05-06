import SwiftUI

struct FooterTerminalOverlay: View {
    let projectID: UUID
    let terminalState: TerminalPaneState?
    let worktreeKey: WorktreeKey?
    let expanded: Bool
    let onToggle: (() -> Void)?
    let onProcessExit: () -> Void

    private let terminalHeight: CGFloat = 320
    private let headerHeight: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
            if let terminalState {
                terminalPanel(state: terminalState)
                    .offset(y: expanded ? 0 : terminalHeight)
                    .allowsHitTesting(expanded)
                    .frame(height: terminalHeight)
                    .clipped()
            }
            CLILauncherFooter(
                projectID: projectID,
                terminalExpanded: expanded,
                onToggleTerminal: onToggle
            )
        }
        .animation(DroidMotion.preferred(DroidMotion.modal, reduceMotion: false), value: expanded)
        .frame(maxWidth: .infinity)
    }

    private func terminalPanel(state: TerminalPaneState) -> some View {
        VStack(spacing: 0) {
            header(state: state)
            TerminalPane(
                state: state,
                focused: expanded,
                visible: expanded,
                onFocus: {},
                onProcessExit: onProcessExit,
                onSplitRequest: { _, _ in }
            )
            .environment(\.activeWorktreeKey, worktreeKey)
            .background(DroidTheme.bg)
        }
        .background(DroidTheme.bg)
        .overlay {
            RoundedRectangle(cornerRadius: 0).stroke(DroidTheme.border, lineWidth: 1)
        }
    }

    private func header(state: TerminalPaneState) -> some View {
        HStack(spacing: 8) {
            DroidIcon(systemName: "terminal", size: 12)
                .foregroundStyle(DroidTheme.fgMuted)
            Text("Footer Terminal")
                .droidFont(size: 12, weight: .semibold)
                .foregroundStyle(DroidTheme.fg)
            Text(state.projectPath)
                .droidFont(size: 11)
                .foregroundStyle(DroidTheme.fgDim)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text(statusText(for: state))
                .droidFont(size: 10, weight: .medium)
                .foregroundStyle(DroidTheme.fgDim)
        }
        .padding(.horizontal, 12)
        .frame(height: headerHeight)
        .background(DroidTheme.secondaryBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DroidTheme.border).frame(height: 1)
        }
    }

    private func statusText(for state: TerminalPaneState) -> String {
        TerminalViewRegistry.shared.needsConfirmQuit(for: state.id) ? "Running" : "Idle"
    }
}
