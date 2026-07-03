import SwiftUI

struct KajiCodeGraphFooterPopover: View {
    let hasGraph: Bool
    let isRunning: Bool
    let hasAgentSession: Bool
    let lastError: String?
    let onView: () -> Void
    let onBuild: () -> Void
    let onUpdate: () -> Void
    let onDelete: () -> Void
    let onShowAgent: () -> Void
    let onCopyCodeGraph: () -> Void
    let onCopyAgentsReference: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let lastError {
                status(message: lastError, icon: "exclamationmark.triangle", color: KajiTheme.diffRemoveFg)
            } else if isRunning {
                status(message: "Graph agent is running", icon: "sparkles", color: KajiTheme.accent)
            } else {
                status(message: hasGraph ? "Graph is ready" : "No graph generated", icon: "circle.fill", color: statusColor)
            }
            VStack(spacing: 4) {
                if hasGraph {
                    action(title: "View Code Graph", icon: "eye", disabled: isRunning, action: onView)
                    action(title: "Update Code Graph", icon: "arrow.clockwise", disabled: isRunning, action: onUpdate)
                    action(title: "Delete Code Graph", icon: "trash", role: .destructive, disabled: isRunning, action: onDelete)
                } else {
                    action(title: "Create Code Graph", icon: "atom", disabled: isRunning, action: onBuild)
                }
                if hasAgentSession {
                    action(title: "Show Graph Agent", icon: "sparkles", disabled: false, action: onShowAgent)
                }
                action(title: "Copy CODE_GRAPH.md", icon: "doc.on.doc", disabled: false, action: onCopyCodeGraph)
                action(title: "Copy AGENTS.md Reference", icon: "link", disabled: false, action: onCopyAgentsReference)
            }
        }
        .padding(10)
        .frame(width: 232)
    }

    private var header: some View {
        HStack(spacing: 8) {
            KajiIcon(systemName: "atom", size: 13)
                .foregroundStyle(KajiTheme.fg)
            Text("Code Graph")
                .kajiFont(size: 13, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Spacer(minLength: 0)
            if isRunning {
                KajiSpinner(size: 12, lineWidth: 1.5)
            }
        }
    }

    private var statusColor: Color {
        hasGraph ? KajiTheme.diffAddFg : KajiTheme.fgDim
    }

    private func status(message: String, icon: String, color: Color) -> some View {
        HStack(spacing: 7) {
            KajiIcon(systemName: icon, size: 10)
                .foregroundStyle(color)
            Text(message)
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.fgMuted)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(KajiTheme.surface, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
    }

    private func action(
        title: String,
        icon: String,
        role: ButtonRole? = nil,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: 8) {
                KajiIcon(systemName: icon, size: 11)
                    .frame(width: 14)
                Text(title)
                    .kajiFont(size: 12, weight: .medium)
                Spacer(minLength: 0)
            }
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(KajiCodeGraphFooterActionStyle(role: role))
        .disabled(disabled)
    }
}

private struct KajiCodeGraphFooterActionStyle: ButtonStyle {
    let role: ButtonRole?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(role == .destructive ? KajiTheme.diffRemoveFg : KajiTheme.fg)
            .padding(.horizontal, 8)
            .background(background(configuration), in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
    }

    private func background(_ configuration: Configuration) -> Color {
        if configuration.isPressed { return KajiTheme.hover }
        return .clear
    }
}
