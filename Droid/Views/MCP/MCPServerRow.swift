import SwiftUI

struct MCPServerRow: View {
    let server: MCPServer
    let status: MCPServerStatus
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusDot
                .padding(.top, 7)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(server.name)
                        .droidFont(size: 13, weight: .semibold)
                        .foregroundStyle(DroidTheme.fg)
                    Text(server.transport.title)
                        .droidFont(size: 10, weight: .medium)
                        .foregroundStyle(DroidTheme.fgDim)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(DroidTheme.surfaceMuted, in: Capsule())
                    Spacer(minLength: 0)
                    DroidSwitch(isOn: Binding(
                        get: { server.enabled },
                        set: { onToggle($0) }
                    ))
                }
                Text(primaryDetail)
                    .droidFont(size: 11, design: .monospaced)
                    .foregroundStyle(DroidTheme.fgMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let source = server.sourceTitle {
                    Text(source)
                        .droidFont(size: 10)
                        .foregroundStyle(DroidTheme.fgDim)
                }
                if let auth = server.authSummary {
                    Text("Auth: \(auth)")
                        .droidFont(size: 10)
                        .foregroundStyle(DroidTheme.fgDim)
                }
                if !server.toolNames.isEmpty {
                    Text(toolSummary)
                        .droidFont(size: 10)
                        .foregroundStyle(DroidTheme.fgDim)
                        .lineLimit(2)
                }
                Text(status.detail)
                    .droidFont(size: 11)
                    .foregroundStyle(DroidTheme.fgDim)
            }
            VStack(spacing: 6) {
                if server.transport != .plugin {
                    Button("Edit", action: onEdit)
                        .buttonStyle(DroidButtonStyle(.secondary, size: .small))
                    Button("Delete", action: onDelete)
                        .buttonStyle(DroidButtonStyle(.danger, size: .small))
                }
            }
        }
        .padding(12)
        .background(DroidTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: DroidShape.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DroidShape.panelRadius)
                .stroke(DroidTheme.border, lineWidth: 1)
        )
    }

    private var statusDot: some View {
        Circle()
            .fill(status.isHealthy ? DroidTheme.diffAddFg : DroidTheme.diffRemoveFg)
            .frame(width: 8, height: 8)
            .help(status.title)
    }

    private var primaryDetail: String {
        switch server.transport {
        case .stdio:
            ([server.command] + server.arguments).filter { !$0.isEmpty }.joined(separator: " ")
        case .remote:
            server.url
        case .plugin:
            server.pluginID ?? "Plugin"
        }
    }

    private var toolSummary: String {
        let visible = server.toolNames.prefix(8).joined(separator: ", ")
        let remaining = max(0, server.toolNames.count - 8)
        return remaining == 0 ? "Tools: \(visible)" : "Tools: \(visible), +\(remaining) more"
    }
}
