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
                placeholder
            } else {
                content
            }
        }
        .background(KajiTheme.bg)
        .task(id: refreshID) {
            state.refreshIfNeeded(projectPath: projectPath, enabledLaunchers: enabledLaunchers)
        }
        .onDisappear {
            state.cancelRefresh()
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
            statusStrip
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

    @ViewBuilder
    private var statusStrip: some View {
        if state.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.mini)
                Text("Refreshing instruction files")
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgDim)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(KajiTheme.secondaryBackground)
            Rectangle().fill(KajiTheme.border.opacity(0.8)).frame(height: 1)
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if state.isLoading {
            loadingState
        } else if let errorMessage = state.errorMessage {
            errorState(errorMessage)
        } else {
            emptyState
        }
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading agent instructions")
                .kajiFont(size: 13, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Text("Scanning instruction files off the main thread.")
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            KajiIcon(systemName: "exclamationmark.triangle", size: 22)
                .foregroundStyle(KajiTheme.diffHunkFg)
            Text("Could not load instructions")
                .kajiFont(size: 13, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Text(message)
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Button("Retry") {
                state.refresh(projectPath: projectPath, enabledLaunchers: enabledLaunchers)
            }
            .buttonStyle(KajiButtonStyle(.secondary, size: .small))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            KajiIcon(systemName: "doc.text", size: 22)
                .foregroundStyle(KajiTheme.fgDim)
            Text(emptyTitle)
                .kajiFont(size: 13, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Text(emptyMessage)
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

    private var emptyTitle: String {
        enabledLaunchers.isEmpty ? "No enabled coding agents" : "No instruction files found"
    }

    private var emptyMessage: String {
        if enabledLaunchers.isEmpty {
            return "Enable Claude Code, Codex, OpenCode, or Pi in Settings to inspect their instruction files."
        }
        return "No AGENTS.md or agent-specific instruction files were found for the enabled agents."
    }
}
