import SwiftUI

struct DroidCodeGraphPane: View {
    @Bindable var state: DroidCodeGraphTabState
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            graphArea
            Rectangle()
                .fill(DroidTheme.border)
                .frame(width: 1)
            sidebar
        }
        .background(DroidTheme.bg)
        .onAppear {
            state.load()
        }
    }

    private var graphArea: some View {
        Group {
            if let document = state.document {
                ZStack(alignment: .topLeading) {
                    switch state.viewMode {
                    case .flow:
                        DroidCodeGraphFlowCanvas(
                            document: document,
                            nodes: state.filteredNodes,
                            selectedNodeID: state.selectedNodeID,
                            onSelect: { state.selectedNodeID = $0 }
                        )
                    case .map:
                        DroidCodeGraphCanvas(
                            document: document,
                            selectedNodeID: state.selectedNodeID,
                            onSelect: { state.selectedNodeID = $0 }
                        )
                    }
                    graphModePicker
                        .padding(10)
                }
            } else {
                VStack(spacing: 10) {
                    if state.isLoading {
                        DroidSpinner(size: 24)
                    } else {
                        DroidIcon(systemName: "point.3.connected.trianglepath.dotted", size: 28)
                            .foregroundStyle(DroidTheme.fgDim)
                    }
                    Text(state.isLoading ? "Loading graph" : (state.errorMessage ?? "No graph loaded"))
                        .droidFont(size: 12)
                        .foregroundStyle(DroidTheme.fgMuted)
                    if !state.isLoading {
                        Button("Reload") {
                            state.load()
                        }
                        .buttonStyle(DroidButtonStyle(.secondary, size: .small))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var graphModePicker: some View {
        SegmentedPicker(
            selection: $state.viewMode,
            options: DroidCodeGraphViewMode.allCases.map { (value: $0, label: $0.label) }
        )
        .frame(width: 136)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(DroidTheme.border).frame(height: 1)
            search
            Rectangle().fill(DroidTheme.border).frame(height: 1)
            nodeList
            Rectangle().fill(DroidTheme.border).frame(height: 1)
            detail
        }
        .frame(width: 284)
        .background(DroidTheme.secondaryBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Code Graph")
                .droidFont(size: 13, weight: .semibold)
                .foregroundStyle(DroidTheme.fg)
            if let document = state.document {
                Text("\(document.nodes.count) nodes · \(document.edges.count) edges · \(document.communities.count) communities")
                    .droidFont(size: 11)
                    .foregroundStyle(DroidTheme.fgDim)
                if let commit = document.git?.shortCommit {
                    Text("\(document.git?.branch ?? "git") @ \(commit)\(document.git?.isDirty == true ? " dirty" : "")")
                        .droidFont(size: 10, design: .monospaced)
                        .foregroundStyle(DroidTheme.fgDim)
                }
            }
            if !state.versions.isEmpty {
                DroidCodeGraphVersionPicker(
                    versions: state.versions,
                    activeVersionID: state.activeVersionID,
                    onLatest: { state.loadLatest() },
                    onSelect: { state.loadVersion($0) }
                )
            }
            Button("Edit AGENTS.md") {
                openInstructions()
            }
            .buttonStyle(DroidButtonStyle(.secondary, size: .small))
        }
        .padding(12)
    }

    private var search: some View {
        DroidInput(
            placeholder: "Search nodes",
            text: $state.query,
            leadingIcon: "magnifyingglass"
        )
        .padding(10)
    }

    private var nodeList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(state.filteredNodes.prefix(120)) { node in
                    Button {
                        state.selectedNodeID = node.id
                    } label: {
                        DroidCodeGraphNodeRow(
                            node: node,
                            selected: node.id == state.selectedNodeID
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let node = state.selectedNode {
                Text(node.label)
                    .droidFont(size: 12, weight: .semibold)
                    .foregroundStyle(DroidTheme.fg)
                    .lineLimit(2)
                if let source = node.sourceFile {
                    Text(source)
                        .droidFont(size: 11, design: .monospaced)
                        .foregroundStyle(DroidTheme.fgDim)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                HStack(spacing: 6) {
                    DroidBadge(text: node.fileType)
                    DroidBadge(text: "degree \(node.degree)")
                    if let community = node.community {
                        DroidBadge(text: "c\(community)")
                    }
                }
            } else {
                Text("Select a node")
                    .droidFont(size: 12)
                    .foregroundStyle(DroidTheme.fgDim)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
    }

    private func openInstructions() {
        guard let file = DroidCodeGraphInstructions.ensureFile(projectID: state.projectID, worktreeID: state.worktreeID) else {
            return
        }
        appState.openFile(file.path, projectID: state.projectID)
    }
}
