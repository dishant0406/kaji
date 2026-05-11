import SwiftUI

struct KajiCodeGraphCanvas: View {
    let document: KajiCodeGraphDocument
    let selectedNodeID: String?
    let onSelect: (String) -> Void
    @State private var scale: CGFloat = 1
    @State private var scaleStart: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragMode: KajiCodeGraphDragMode?
    @State private var nodeOffsets: [String: CGSize] = [:]

    var body: some View {
        GeometryReader { proxy in
            let layout = KajiCodeGraphLayout(document: document, size: proxy.size, nodeOffsets: nodeOffsets)
            Canvas { context, _ in
                var transformed = context
                transformed.translateBy(x: offset.width, y: offset.height)
                transformed.scaleBy(x: scale, y: scale)
                drawEdges(context: transformed, layout: layout)
                drawNodes(context: transformed, layout: layout)
                drawLabels(context: transformed, layout: layout)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(size: proxy.size))
            .simultaneousGesture(zoomGesture)
            .overlay(alignment: .bottomLeading) {
                KajiCodeGraphZoomControls(
                    resetLabel: "Reset Graph View",
                    onZoomOut: zoomOut,
                    onZoomIn: zoomIn,
                    onReset: resetView
                )
            }
        }
    }

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let mode = dragMode ?? beginDrag(at: value.startLocation, size: size)
                dragMode = mode
                updateDrag(mode, translation: value.translation)
            }
            .onEnded { value in
                endDrag(value, size: size)
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

    private func drawEdges(context: GraphicsContext, layout: KajiCodeGraphLayout) {
        for edge in document.edges.prefix(2400) {
            guard let source = layout.positions[edge.source], let target = layout.positions[edge.target] else { continue }
            var path = Path()
            path.move(to: source)
            path.addLine(to: target)
            let selected = edge.source == selectedNodeID || edge.target == selectedNodeID
            context.stroke(
                path,
                with: .color(KajiCodeGraphPalette.edge(selected: selected)),
                lineWidth: selected ? 1.3 : 0.7
            )
        }
    }

    private func drawNodes(context: GraphicsContext, layout: KajiCodeGraphLayout) {
        for node in document.nodes.prefix(1800) {
            guard let point = layout.positions[node.id] else { continue }
            let selected = node.id == selectedNodeID
            let radius = selected ? 7.5 : max(3.5, min(6.5, CGFloat(node.degree) * 0.35 + 3.5))
            let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            let color = KajiCodeGraphPalette.color(for: node.community)
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(selected ? 1 : 0.82)))
            context.stroke(Path(ellipseIn: rect), with: .color(KajiCodeGraphPalette.nodeStroke(selected: false)), lineWidth: 1)
            if selected {
                context.stroke(
                    Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)),
                    with: .color(KajiCodeGraphPalette.nodeStroke(selected: true)),
                    lineWidth: 1.4
                )
            }
        }
    }

    private func drawLabels(context: GraphicsContext, layout: KajiCodeGraphLayout) {
        for node in labeledNodes {
            guard let point = layout.positions[node.id] else { continue }
            let selected = node.id == selectedNodeID
            let radius = selected ? 7.5 : max(3.5, min(6.5, CGFloat(node.degree) * 0.35 + 3.5))
            let label = Text(node.label)
                .font(.system(size: selected ? 10.5 : 9.5, weight: selected ? .semibold : .medium))
                .foregroundColor(KajiCodeGraphPalette.label(selected: selected))
            context.draw(label, at: CGPoint(x: point.x + radius + 5, y: point.y), anchor: .leading)
        }
    }

    private var labeledNodes: [KajiCodeGraphNode] {
        let selected = document.nodes.first { $0.id == selectedNodeID }
        let prominent = document.nodes
            .filter { $0.degree >= 6 }
            .sorted { $0.degree > $1.degree }
            .prefix(60)
        return ([selected].compactMap(\.self) + prominent).uniquedByID()
    }

    private func beginDrag(at location: CGPoint, size: CGSize) -> KajiCodeGraphDragMode {
        let graphPoint = graphPoint(from: location)
        let layout = KajiCodeGraphLayout(document: document, size: size, nodeOffsets: nodeOffsets)
        if let nodeID = layout.nearestNode(to: graphPoint, maxDistance: 18 / scale) {
            onSelect(nodeID)
            return .node(id: nodeID, start: nodeOffsets[nodeID] ?? .zero)
        }
        return .canvas(start: offset)
    }

    private func updateDrag(_ mode: KajiCodeGraphDragMode, translation: CGSize) {
        switch mode {
        case let .canvas(start):
            offset = CGSize(width: start.width + translation.width, height: start.height + translation.height)
        case let .node(id, start):
            nodeOffsets[id] = CGSize(
                width: start.width + translation.width / scale,
                height: start.height + translation.height / scale
            )
        }
    }

    private func endDrag(_ value: DragGesture.Value, size: CGSize) {
        if abs(value.translation.width) < 4, abs(value.translation.height) < 4 {
            selectNearest(to: value.location, size: size)
        }
        dragMode = nil
    }

    private func selectNearest(to location: CGPoint, size: CGSize) {
        let layout = KajiCodeGraphLayout(document: document, size: size, nodeOffsets: nodeOffsets)
        if let nodeID = layout.nearestNode(to: graphPoint(from: location), maxDistance: 18 / scale) {
            onSelect(nodeID)
        }
    }

    private func graphPoint(from location: CGPoint) -> CGPoint {
        CGPoint(
            x: (location.x - offset.width) / scale,
            y: (location.y - offset.height) / scale
        )
    }
}

private enum KajiCodeGraphDragMode {
    case canvas(start: CGSize)
    case node(id: String, start: CGSize)
}
