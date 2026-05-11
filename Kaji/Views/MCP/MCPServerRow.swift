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
                        .kajiFont(size: 13, weight: .semibold)
                        .foregroundStyle(KajiTheme.fg)
                    Text(server.transport.title)
                        .kajiFont(size: 10, weight: .medium)
                        .foregroundStyle(KajiTheme.fgDim)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(KajiTheme.surfaceMuted, in: Capsule())
                    Spacer(minLength: 0)
                    KajiSwitch(isOn: Binding(
                        get: { server.enabled },
                        set: { onToggle($0) }
                    ))
                }
                Text(primaryDetail)
                    .kajiFont(size: 11, design: .monospaced)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let source = server.sourceTitle {
                    Text(source)
                        .kajiFont(size: 10)
                        .foregroundStyle(KajiTheme.fgDim)
                }
                if let auth = server.authSummary {
                    Text("Auth: \(auth)")
                        .kajiFont(size: 10)
                        .foregroundStyle(KajiTheme.fgDim)
                }
                if !server.toolNames.isEmpty {
                    Text(toolSummary)
                        .kajiFont(size: 10)
                        .foregroundStyle(KajiTheme.fgDim)
                        .lineLimit(2)
                }
                Text(status.detail)
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            VStack(spacing: 6) {
                if server.transport != .plugin {
                    Button("Edit", action: onEdit)
                        .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    Button("Delete", action: onDelete)
                        .buttonStyle(KajiButtonStyle(.danger, size: .small))
                }
            }
        }
        .padding(12)
        .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: KajiShape.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: KajiShape.panelRadius)
                .stroke(KajiTheme.border, lineWidth: 1)
        )
    }

    private var statusDot: some View {
        Circle()
            .fill(status.isHealthy ? KajiTheme.diffAddFg : KajiTheme.diffRemoveFg)
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
