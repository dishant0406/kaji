import SwiftUI

struct MCPServerControlPanel: View {
    let projectPath: String?
    let onDismiss: () -> Void

    @State private var store = MCPServerConfigStore.shared
    @State private var selectedAgentID = ""
    @State private var editor: MCPServerEditorState?

    var body: some View {
        Group {
            if let editor {
                MCPServerEditorView(
                    state: editor,
                    onCancel: { self.editor = nil },
                    onSave: save
                )
            } else {
                panel
            }
        }
        .frame(width: 860, height: 560)
        .background(DroidTheme.bg, in: RoundedRectangle(cornerRadius: DroidShape.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DroidShape.panelRadius)
                .stroke(DroidTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 22, x: 0, y: 12)
        .task(id: projectPath ?? "") {
            store.load(projectPath: projectPath)
            selectedAgentID = store.panels.first?.agent.id ?? ""
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DroidTheme.border)
            content
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            DroidIcon(systemName: "network", size: 15)
                .foregroundStyle(DroidTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("MCP Control Panel")
                    .droidFont(size: 15, weight: .semibold)
                    .foregroundStyle(DroidTheme.fg)
                Text("Manage coding agent MCP servers and write changes back to their config files.")
                    .droidFont(size: 11)
                    .foregroundStyle(DroidTheme.fgDim)
            }
            Spacer(minLength: 0)
            if store.isLoading {
                DroidSpinner(size: 13)
            }
            Button("Reload") { store.load(projectPath: projectPath) }
                .buttonStyle(DroidButtonStyle(.secondary, size: .small))
            IconButton(symbol: "xmark", accessibilityLabel: "Close MCP Control Panel", action: onDismiss)
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }

    @ViewBuilder
    private var content: some View {
        if store.panels.isEmpty {
            VStack(spacing: 8) {
                Text("No MCP-compatible coding agents found")
                    .droidFont(size: 13, weight: .semibold)
                    .foregroundStyle(DroidTheme.fg)
                Text("Open a project to manage project-scoped MCP files.")
                    .droidFont(size: 12)
                    .foregroundStyle(DroidTheme.fgDim)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 0) {
                agentTabs
                Divider().overlay(DroidTheme.border)
                activeAgentPanel
            }
        }
    }

    private var agentTabs: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(store.panels) { panel in
                MCPAgentTabRow(
                    panel: panel,
                    selected: selectedAgentID == panel.agent.id,
                    count: panel.servers.count
                ) {
                    selectedAgentID = panel.agent.id
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 190)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DroidTheme.secondaryBackground)
    }

    @ViewBuilder
    private var activeAgentPanel: some View {
        if let panel = selectedPanel {
            MCPAgentServersView(
                panel: panel,
                status: store.status,
                onAdd: { editor = MCPServerEditorState(agentID: panel.agent.id, server: .empty(), originalName: nil) },
                onEdit: { server in editor = MCPServerEditorState(agentID: panel.agent.id, server: server, originalName: server.name) },
                onDelete: { server in store.delete(serverName: server.name, agentID: panel.agent.id) },
                onToggle: { server, enabled in store.toggle(serverName: server.name, agentID: panel.agent.id, enabled: enabled) }
            )
        }
    }

    private var selectedPanel: MCPAgentPanelState? {
        store.panels.first { $0.agent.id == selectedAgentID } ?? store.panels.first
    }

    private func save(_ state: MCPServerEditorState) {
        store.upsert(state.server, agentID: state.agentID, originalName: state.originalName)
        if store.panels.first(where: { $0.agent.id == state.agentID })?.errorMessage == nil {
            editor = nil
        }
    }
}
