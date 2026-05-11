import SwiftUI

struct ProjectContextMenu: View {
    let hasLogo: Bool
    let hasIconColor: Bool
    let isGitRepo: Bool
    let canSwitchWorktree: Bool
    let isRefreshingWorktrees: Bool
    let isCodeGraphInstalled: Bool
    let isCodeGraphEnabled: Bool
    let hasCodeGraph: Bool
    let isCodeGraphRunning: Bool
    let hasCodeGraphAgentSession: Bool
    let onSetLogo: () -> Void
    let onRemoveLogo: () -> Void
    let onSetIconColor: () -> Void
    let onResetIconColor: () -> Void
    let onRename: () -> Void
    let onRefreshWorktrees: () -> Void
    let onNewWorktree: () -> Void
    let onSwitchWorktree: () -> Void
    let onInstallCodeGraph: () -> Void
    let onEnableCodeGraph: () -> Void
    let onBuildCodeGraph: () -> Void
    let onUpdateCodeGraph: () -> Void
    let onViewCodeGraph: () -> Void
    let onShowCodeGraphAgent: () -> Void
    let onRemoveProject: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            ProjectContextMenuButton(title: "Set Logo...", icon: "photo", action: onSetLogo)
            if hasLogo {
                ProjectContextMenuButton(title: "Remove Logo", icon: "trash", action: onRemoveLogo)
            }
            ProjectContextMenuButton(title: "Set Icon Color...", icon: "paintpalette", action: onSetIconColor)
            if hasIconColor {
                ProjectContextMenuButton(title: "Reset Icon Color", icon: "arrow.counterclockwise", action: onResetIconColor)
            }

            ProjectContextMenuDivider()
            ProjectContextMenuButton(title: "Rename Project", icon: "pencil", action: onRename)

            if isGitRepo {
                ProjectContextMenuDivider()
                ProjectContextMenuButton(
                    title: "Refresh Worktrees",
                    icon: "arrow.clockwise",
                    isBusy: isRefreshingWorktrees,
                    action: onRefreshWorktrees
                )
                ProjectContextMenuButton(title: "New Worktree...", icon: "plus", action: onNewWorktree)
                if canSwitchWorktree {
                    ProjectContextMenuButton(title: "Switch Worktree...", icon: "arrow.left.arrow.right", action: onSwitchWorktree)
                }
            }

            ProjectContextMenuDivider()
            if !isCodeGraphInstalled {
                ProjectContextMenuButton(title: "Install KajiCodeGraph...", icon: "puzzlepiece.extension", action: onInstallCodeGraph)
            } else if !isCodeGraphEnabled {
                ProjectContextMenuButton(title: "Enable KajiCodeGraph", icon: "power", action: onEnableCodeGraph)
            } else {
                ProjectContextMenuButton(
                    title: hasCodeGraph ? "Rebuild Code Graph" : "Build Code Graph",
                    icon: "point.3.connected.trianglepath.dotted",
                    isBusy: isCodeGraphRunning,
                    action: onBuildCodeGraph
                )
                if hasCodeGraph {
                    ProjectContextMenuButton(
                        title: "Update Code Graph",
                        icon: "arrow.clockwise",
                        isBusy: isCodeGraphRunning,
                        action: onUpdateCodeGraph
                    )
                    ProjectContextMenuButton(title: "View Code Graph", icon: "eye", action: onViewCodeGraph)
                }
                if hasCodeGraphAgentSession {
                    ProjectContextMenuButton(title: "Show Graph Agent", icon: "sparkles", action: onShowCodeGraphAgent)
                }
            }

            ProjectContextMenuDivider()
            ProjectContextMenuButton(
                title: "Remove Project",
                icon: "trash",
                role: .destructive,
                action: onRemoveProject
            )
        }
        .padding(5)
        .frame(width: 224)
        .background(
            TranslucentSurface(
                base: KajiTheme.tertiaryBackground,
                material: .menu,
                tintOpacity: 0.82
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: KajiShape.panelRadius))
        .overlay {
            RoundedRectangle(cornerRadius: KajiShape.panelRadius)
                .strokeBorder(KajiTheme.border.opacity(0.78), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 8)
    }
}

private struct ProjectContextMenuButton: View {
    let title: String
    let icon: String
    var role: ButtonRole?
    var isBusy = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 7) {
                if isBusy {
                    KajiSpinner(size: 11, lineWidth: 1.4)
                        .frame(width: 13, height: 13)
                } else {
                    KajiIcon(systemName: icon, size: 11)
                        .frame(width: 13, height: 13)
                }

                Text(title)
                    .kajiFont(size: 12, weight: .medium)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(hovered ? KajiTheme.surface : .clear, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
            .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .onHover { hovered = $0 }
        .kajiPointer()
    }

    private var foreground: Color {
        if role == .destructive {
            return hovered ? KajiTheme.diffRemoveFg : KajiTheme.diffRemoveFg.opacity(0.86)
        }
        return hovered ? KajiTheme.fg : KajiTheme.fgMuted
    }
}

private struct ProjectContextMenuDivider: View {
    var body: some View {
        Rectangle()
            .fill(KajiTheme.border.opacity(0.64))
            .frame(height: 1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
    }
}
