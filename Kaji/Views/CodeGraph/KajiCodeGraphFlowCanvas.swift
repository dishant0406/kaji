import SwiftUI

struct KajiCodeGraphFlowCanvas: View {
    let document: KajiCodeGraphDocument
    let nodes: [KajiCodeGraphNode]
    let selectedNodeID: String?
    let onSelect: (String) -> Void
    @State private var scale: CGFloat = 1
    @State private var scaleStart: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragMode: KajiCodeGraphFlowDragMode?
    @State private var nodeOffsets: [String: CGSize] = [:]

    var body: some View {
        GeometryReader { proxy in
            let displayNodes = displayedNodes
            let layout = KajiCodeGraphFlowLayout(
                document: document,
                nodes: displayNodes,
                viewportSize: proxy.size,
                nodeOffsets: nodeOffsets
            )
            Canvas { context, _ in
                var transformed = context
                transformed.translateBy(x: offset.width, y: offset.height)
                transformed.scaleBy(x: scale, y: scale)
                drawEdges(context: transformed, layout: layout)
                drawNodes(context: transformed, layout: layout, nodes: displayNodes)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(layout: layout))
            .simultaneousGesture(zoomGesture)
            .overlay(alignment: .bottomLeading) {
                KajiCodeGraphZoomControls(
                    resetLabel: "Reset Graph Flow View",
                    onZoomOut: zoomOut,
                    onZoomIn: zoomIn,
                    onReset: resetView
                )
            }
        }
    }

    private func dragGesture(layout: KajiCodeGraphFlowLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragMode == nil {
                    dragMode = beginDrag(at: value.startLocation, layout: layout)
                }
                updateDrag(translation: value.translation)
            }
            .onEnded { value in
                if abs(value.translation.width) < 4, abs(value.translation.height) < 4 {
                    selectNode(at: value.location, layout: layout)
                }
                dragMode = nil
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = KajiCodeGraphScale.clamped(scaleStart * value)
            }
            .onEnded { value in
                scale = KajiCodeGraphScale.clamped(scaleStart * value)
                scaleStart = scale
            }
    }

    private func beginDrag(at location: CGPoint, layout: KajiCodeGraphFlowLayout) -> KajiCodeGraphFlowDragMode {
        if let nodeID = layout.node(at: graphPoint(from: location)) {
            onSelect(nodeID)
            return .node(id: nodeID, start: nodeOffsets[nodeID] ?? .zero)
        }
        return .canvas(start: offset)
    }

    private func updateDrag(translation: CGSize) {
        switch dragMode {
        case let .node(id, start):
            nodeOffsets[id] = CGSize(width: start.width + translation.width / scale, height: start.height + translation.height / scale)
        case let .canvas(start):
            offset = CGSize(width: start.width + translation.width, height: start.height + translation.height)
        case nil:
            break
        }
    }

    private func selectNode(at location: CGPoint, layout: KajiCodeGraphFlowLayout) {
        if let nodeID = layout.node(at: graphPoint(from: location)) {
            onSelect(nodeID)
        }
    }

    private func zoomOut() {
        scale = KajiCodeGraphScale.clamped(scale - 0.15)
        scaleStart = scale
    }

    private func zoomIn() {
        scale = KajiCodeGraphScale.clamped(scale + 0.15)
        scaleStart = scale
    }

    private func resetView() {
        scale = 1
        scaleStart = 1
        offset = .zero
        dragMode = nil
        nodeOffsets = [:]
    }

    private func drawEdges(context: GraphicsContext, layout: KajiCodeGraphFlowLayout) {
        let edges = visibleEdges(layout: layout)
        for edge in edges where !isSelected(edge) {
            draw(edge, context: context, layout: layout)
        }
        for edge in edges where isSelected(edge) {
            draw(edge, context: context, layout: layout)
        }
    }

    private func draw(_ edge: KajiCodeGraphEdge, context: GraphicsContext, layout: KajiCodeGraphFlowLayout) {
        guard let source = layout.nodeFrames[edge.source], let target = layout.nodeFrames[edge.target] else { return }
        let selected = isSelected(edge)
        var path = Path()
        path.move(to: source.center)
        path.addCurve(
            to: target.center,
            control1: CGPoint(x: source.midX, y: (source.midY + target.midY) / 2),
            control2: CGPoint(x: target.midX, y: (source.midY + target.midY) / 2)
        )
        context.stroke(path, with: .color(KajiCodeGraphPalette.edge(selected: selected)), lineWidth: selected ? 1.2 : 0.75)
    }

    private func drawNodes(context: GraphicsContext, layout: KajiCodeGraphFlowLayout, nodes: [KajiCodeGraphNode]) {
        for node in nodes.sortedForFlow(selectedNodeID: selectedNodeID) {
            draw(node, frame: layout.nodeFrames[node.id], context: context)
        }
    }

    private func draw(_ node: KajiCodeGraphNode, frame: CGRect?, context: GraphicsContext) {
        guard let frame else { return }
        let selected = node.id == selectedNodeID
        context.fill(
            Path(roundedRect: frame, cornerRadius: KajiShape.tileRadius),
            with: .color(selected ? KajiTheme.accentSoft.opacity(0.72) : KajiTheme.surface)
        )
        context.stroke(
            Path(roundedRect: frame, cornerRadius: KajiShape.tileRadius),
            with: .color(selected ? KajiTheme.accent : KajiTheme.border),
            lineWidth: selected ? 1.3 : 1
        )
        context.draw(label(for: node, selected: selected), at: CGPoint(x: frame.minX + 11, y: frame.minY + 12), anchor: .leading)
        context.draw(subtitle(for: node), at: CGPoint(x: frame.minX + 11, y: frame.minY + 28), anchor: .leading)
        context.fill(
            Path(ellipseIn: CGRect(x: frame.maxX - 18, y: frame.midY - 4, width: 8, height: 8)),
            with: .color(KajiCodeGraphPalette.color(for: node.community))
        )
    }

    private func visibleEdges(layout: KajiCodeGraphFlowLayout) -> [KajiCodeGraphEdge] {
        document.edges.filter {
            layout.nodeFrames[$0.source] != nil && layout.nodeFrames[$0.target] != nil
        }.prefix(2400).map(\.self)
    }

    private var displayedNodes: [KajiCodeGraphNode] {
        let nodeByID = document.nodeByID
        let neighborIDs = Set(document.edges.compactMap { edge in
            if edge.source == selectedNodeID { return edge.target }
            if edge.target == selectedNodeID { return edge.source }
            return nil
        })
        let selected = selectedNodeID.flatMap { nodeByID[$0] }
        let neighbors = Array(neighborIDs.compactMap { nodeByID[$0] }.sorted { $0.degree > $1.degree }.prefix(60))
        return (Array(nodes.prefix(160)) + [selected].compactMap(\.self) + neighbors).uniquedByID()
    }

    private func isSelected(_ edge: KajiCodeGraphEdge) -> Bool {
        guard let selectedNodeID else { return false }
        return edge.source == selectedNodeID || edge.target == selectedNodeID
    }

    private func graphPoint(from location: CGPoint) -> CGPoint {
        CGPoint(x: (location.x - offset.width) / scale, y: (location.y - offset.height) / scale)
    }

    private func label(for node: KajiCodeGraphNode, selected: Bool) -> Text {
        Text(node.label).font(.system(size: 11, weight: selected ? .semibold : .medium))
            .foregroundColor(KajiCodeGraphPalette.label(selected: selected))
    }

    private func subtitle(for node: KajiCodeGraphNode) -> Text {
        Text(node.sourceFile ?? node.fileType).font(.system(size: 9.5, weight: .regular, design: .monospaced))
            .foregroundColor(KajiTheme.fgDim)
    }
}
