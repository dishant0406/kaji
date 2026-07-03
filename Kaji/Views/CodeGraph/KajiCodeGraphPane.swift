import SwiftUI

struct KajiCodeGraphPane: View {
    @Bindable var state: KajiCodeGraphTabState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            graphArea
            Rectangle()
                .fill(KajiTheme.border)
                .frame(width: 1)
            sidebar
        }
        .background(KajiTheme.bg)
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
                        KajiCodeGraphFlowCanvas(
                            document: document,
                            nodes: state.filteredNodes,
                            selectedNodeID: state.selectedNodeID,
                            onSelect: { selectNode($0) }
                        )
                    case .map:
                        KajiCodeGraphCanvas(
                            document: document,
                            selectedNodeID: state.selectedNodeID,
                            onSelect: { selectNode($0) }
                        )
                    }
                    graphModePicker
                        .padding(10)
                }
            } else {
                VStack(spacing: 10) {
                    if state.isLoading {
                        KajiSpinner(size: 24)
                    } else {
                        KajiIcon(systemName: "point.3.connected.trianglepath.dotted", size: 28)
                            .foregroundStyle(KajiTheme.fgDim)
                    }
                    Text(state.isLoading ? "Loading graph" : (state.errorMessage ?? "No graph loaded"))
                        .kajiFont(size: 12)
                        .foregroundStyle(KajiTheme.fgMuted)
                    if !state.isLoading {
                        Button("Reload") {
                            state.load()
                        }
                        .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .transition(KajiMotion.contentSwitchTransition(reduceMotion: reduceMotion))
        .animation(KajiMotion.preferred(KajiMotion.panel, reduceMotion: reduceMotion), value: state.viewMode)
        .animation(KajiMotion.preferred(KajiMotion.panel, reduceMotion: reduceMotion), value: state.activeVersionID)
    }

    private var graphModePicker: some View {
        SegmentedPicker(
            selection: $state.viewMode,
            options: KajiCodeGraphViewMode.allCases.map { (value: $0, label: $0.label) }
        )
        .frame(width: 136)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(KajiTheme.border).frame(height: 1)
            search
            Rectangle().fill(KajiTheme.border).frame(height: 1)
            nodeList
            Rectangle().fill(KajiTheme.border).frame(height: 1)
            detail
        }
        .frame(width: 284)
        .background(KajiTheme.secondaryBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Code Graph")
                .kajiFont(size: 13, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            if let document = state.document {
                Text("\(document.nodes.count) nodes · \(document.edges.count) edges · \(document.communities.count) communities")
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgDim)
                if let commit = document.git?.shortCommit {
                    Text("\(document.git?.branch ?? "git") @ \(commit)\(document.git?.isDirty == true ? " dirty" : "")")
                        .kajiFont(size: 10, design: .monospaced)
                        .foregroundStyle(KajiTheme.fgDim)
                }
            }
            if !state.versions.isEmpty {
                KajiCodeGraphVersionPicker(
                    versions: state.versions,
                    activeVersionID: state.activeVersionID,
                    onLatest: { state.loadLatest() },
                    onSelect: { state.loadVersion($0) }
                )
            }
            Button("Copy CODE_GRAPH.md") {
                KajiCodeGraphPromptClipboard.copyCodeGraphDocument()
            }
            .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            Button("Copy AGENTS.md Reference") {
                KajiCodeGraphPromptClipboard.copyAgentsReference()
            }
            .buttonStyle(KajiButtonStyle(.secondary, size: .small))
        }
        .padding(12)
    }

    private var search: some View {
        KajiInput(
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
                        selectNode(node.id)
                    } label: {
                        KajiCodeGraphNodeRow(
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
                    .kajiFont(size: 12, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                    .lineLimit(2)
                if let source = node.sourceFile {
                    Text(source)
                        .kajiFont(size: 11, design: .monospaced)
                        .foregroundStyle(KajiTheme.fgDim)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                HStack(spacing: 6) {
                    KajiBadge(text: node.fileType)
                    KajiBadge(text: "degree \(node.degree)")
                    if let community = node.community {
                        KajiBadge(text: "c\(community)")
                    }
                }
            } else {
                Text("Select a node")
                    .kajiFont(size: 12)
                    .foregroundStyle(KajiTheme.fgDim)
            }
        }
        .id(state.selectedNodeID ?? "empty")
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
    }

    private func selectNode(_ nodeID: String?) {
        state.selectedNodeID = nodeID
    }
}
