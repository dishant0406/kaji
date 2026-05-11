import SwiftUI

struct FooterTerminalOverlay: View {
    let projectID: UUID
    let terminalState: TerminalPaneState?
    let worktreeKey: WorktreeKey?
    let worktreePath: String?
    let expanded: Bool
    let onToggle: (() -> Void)?
    let onOpenMCPControlPanel: (() -> Void)?
    let onProcessExit: () -> Void

    private let terminalHeight: CGFloat = 320
    private let headerHeight: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
            if let terminalState, expanded {
                terminalPanel(state: terminalState)
                    .frame(height: terminalHeight)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            CLILauncherFooter(
                projectID: projectID,
                worktreeKey: worktreeKey,
                worktreePath: worktreePath,
                terminalExpanded: expanded,
                onToggleTerminal: onToggle,
                onOpenMCPControlPanel: onOpenMCPControlPanel
            )
        }
        .animation(KajiMotion.preferred(KajiMotion.modal, reduceMotion: false), value: expanded)
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
            .background(KajiTheme.bg)
        }
        .background(KajiTheme.bg)
        .overlay {
            RoundedRectangle(cornerRadius: 0).stroke(KajiTheme.border, lineWidth: 1)
        }
    }

    private func header(state: TerminalPaneState) -> some View {
        HStack(spacing: 8) {
            KajiIcon(systemName: "terminal", size: 12)
                .foregroundStyle(KajiTheme.fgMuted)
            Text("Footer Terminal")
                .kajiFont(size: 12, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Text(state.projectPath)
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.fgDim)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text(statusText(for: state))
                .kajiFont(size: 10, weight: .medium)
                .foregroundStyle(KajiTheme.fgDim)
        }
        .padding(.horizontal, 12)
        .frame(height: headerHeight)
        .background(KajiTheme.secondaryBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(KajiTheme.border).frame(height: 1)
        }
    }

    private func statusText(for state: TerminalPaneState) -> String {
        TerminalViewRegistry.shared.needsConfirmQuit(for: state.id) ? "Running" : "Idle"
    }
}
