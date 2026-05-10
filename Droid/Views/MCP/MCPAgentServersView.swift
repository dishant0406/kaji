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
            Divider().overlay(DroidTheme.border)
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
                        .droidFont(size: 14, weight: .semibold)
                        .foregroundStyle(DroidTheme.fg)
                    if panel.loadState.isLoading {
                        DroidSpinner(size: 12)
                    }
                }
                Text(configSummary)
                    .droidFont(size: 11, design: .monospaced)
                    .foregroundStyle(DroidTheme.fgDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button("Add Server", action: onAdd)
                .buttonStyle(DroidButtonStyle(.primary, size: .small))
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
            DroidIcon(systemName: "network", size: 22)
                .foregroundStyle(DroidTheme.fgDim)
            Text("No MCP servers configured")
                .droidFont(size: 13, weight: .semibold)
                .foregroundStyle(DroidTheme.fg)
            Text("Add stdio or remote servers here. Droid will create or update the config file automatically.")
                .droidFont(size: 12)
                .foregroundStyle(DroidTheme.fgDim)
            Button("Add Server", action: onAdd)
                .buttonStyle(DroidButtonStyle(.secondary, size: .small))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            DroidSpinner(size: 18)
            Text("Scanning MCP sources")
                .droidFont(size: 13, weight: .semibold)
                .foregroundStyle(DroidTheme.fg)
            Text("The panel stays usable while config files and runtime caches load.")
                .droidFont(size: 12)
                .foregroundStyle(DroidTheme.fgDim)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
