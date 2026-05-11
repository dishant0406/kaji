import SwiftUI

struct MCPAgentServersView: View {
    let panel: MCPAgentPanelState
    let status: (MCPServer) -> MCPServerStatus
    let onAdd: () -> Void
    let onEdit: (MCPServer) -> Void
    let onDelete: (MCPServer) -> Void
    let onToggle: (MCPServer, Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(KajiTheme.border)
            if panel.loadState.isLoading, panel.servers.isEmpty {
                loadingState
            } else if panel.servers.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(panel.servers) { server in
                            MCPServerRow(
                                server: server,
                                status: status(server),
                                onEdit: { onEdit(server) },
                                onDelete: { onDelete(server) },
                                onToggle: { enabled in onToggle(server, enabled) }
                            )
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(panel.agent.displayName)
                        .kajiFont(size: 14, weight: .semibold)
                        .foregroundStyle(KajiTheme.fg)
                    if panel.loadState.isLoading {
                        KajiSpinner(size: 12)
                    }
                }
                Text(configSummary)
                    .kajiFont(size: 11, design: .monospaced)
                    .foregroundStyle(KajiTheme.fgDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button("Add Server", action: onAdd)
                .buttonStyle(KajiButtonStyle(.primary, size: .small))
        }
        .padding(.horizontal, 14)
        .frame(height: 64)
    }

    private var configSummary: String {
        let count = panel.locations.count
        guard count != 1 else {
            let location = panel.locations[0]
            return "\(location.scope.title) config: \(location.url.path)"
        }
        return "Reading \(count) config sources"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            KajiIcon(systemName: "mcp", size: 22)
                .foregroundStyle(KajiTheme.fgDim)
            Text("No MCP servers configured")
                .kajiFont(size: 13, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Text("Add stdio or remote servers here. Kaji will create or update the config file automatically.")
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgDim)
            Button("Add Server", action: onAdd)
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            KajiSpinner(size: 18)
            Text("Scanning MCP sources")
                .kajiFont(size: 13, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Text("The panel stays usable while config files and runtime caches load.")
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgDim)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
