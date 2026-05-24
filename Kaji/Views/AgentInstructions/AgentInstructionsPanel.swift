import SwiftUI

struct AgentInstructionsPanel: View {
    @Bindable var state: AgentInstructionPanelState
    let projectPath: String
    let enabledLaunchers: [CLILauncherConfiguration]
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(KajiTheme.border).frame(height: 1)
            if state.groups.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .background(KajiTheme.bg)
        .task(id: refreshID) {
            state.refresh(projectPath: projectPath, enabledLaunchers: enabledLaunchers)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            KajiIcon(systemName: "doc.text.magnifyingglass", size: 13)
                .foregroundStyle(KajiTheme.fgMuted)
            Text("Agent Instructions")
                .kajiFont(size: 13, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Spacer(minLength: 0)
            IconButton(symbol: "xmark", size: 11, accessibilityLabel: "Close Agent Instructions", action: onClose)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(KajiTheme.secondaryBackground)
    }

    private var content: some View {
        VStack(spacing: 0) {
            agentTabs
            Rectangle().fill(KajiTheme.border).frame(height: 1)
            if selectedDocuments.count > 1 {
                AgentInstructionDocumentTabs(
                    documents: selectedDocuments,
                    selectedDocumentID: state.selectedDocument?.id,
                    onSelect: state.selectDocument
                )
                Rectangle().fill(KajiTheme.border).frame(height: 1)
            }
            AgentInstructionMarkdownPreview(document: state.selectedDocument, projectPath: projectPath)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var agentTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(state.groups) { group in
                    AgentInstructionTab(
                        group: group,
                        selected: group.id == state.selectedGroup?.id
                    ) {
                        state.selectAgent(group.id)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(KajiTheme.secondaryBackground)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            KajiIcon(systemName: "doc.text", size: 22)
                .foregroundStyle(KajiTheme.fgDim)
            Text("No enabled coding agents")
                .kajiFont(size: 13, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Text("Enable Claude Code, Codex, OpenCode, or Pi in Settings to inspect their instruction files.")
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var refreshID: String {
        ([projectPath] + enabledLaunchers.map { "\($0.id):\($0.isEnabled)" }).joined(separator: "|")
    }

    private var selectedDocuments: [AgentInstructionDocument] {
        state.selectedGroup?.documents ?? []
    }
}
