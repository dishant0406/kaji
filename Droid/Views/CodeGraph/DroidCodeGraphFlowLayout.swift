import CoreGraphics

struct DroidCodeGraphFlowLayout {
    let nodeFrames: [String: CGRect]
    let contentSize: CGSize
    private let nodeIDs: [String]

    init(document _: DroidCodeGraphDocument, nodes: [DroidCodeGraphNode], viewportSize: CGSize, nodeOffsets: [String: CGSize] = [:]) {
        let sortedNodes = nodes.uniquedByID().sorted {
            $0.degree == $1.degree ? $0.label < $1.label : $0.degree > $1.degree
        }
        let cardSize = CGSize(width: 232, height: 46)
        let padding: CGFloat = 78
        let size = CGSize(width: max(viewportSize.width * 1.7, 960), height: max(viewportSize.height * 1.45, 700))
        let metrics = DroidCodeGraphFlowLayoutMetrics(
            center: CGPoint(x: size.width / 2, y: size.height / 2),
            bounds: size,
            cardSize: cardSize,
            padding: padding
        )
        var frames: [String: CGRect] = [:]
        var ids: [String] = []
        for (index, node) in sortedNodes.enumerated() {
            let point = Self.point(for: node, index: index, metrics: metrics)
            let offset = nodeOffsets[node.id] ?? .zero
            let origin = CGPoint(x: point.x - cardSize.width / 2 + offset.width, y: point.y - cardSize.height / 2 + offset.height)
            frames[node.id] = CGRect(origin: origin.clamped(to: size, cardSize: cardSize, padding: padding), size: cardSize)
            ids.append(node.id)
        }
        nodeFrames = frames
        contentSize = size
        nodeIDs = ids
    }

    func node(at point: CGPoint) -> String? {
        nodeIDs.reversed().first { nodeFrames[$0]?.contains(point) == true }
    }

    private static func point(
        for node: DroidCodeGraphNode,
        index: Int,
        metrics: DroidCodeGraphFlowLayoutMetrics
    ) -> CGPoint {
        let ring = CGFloat(index / 18)
        let angle = CGFloat(index) * 2.399963229728653 + stableUnit(node.id) * CGFloat.pi * 0.62
        let radius = 96 + ring * 108 + stableUnit(node.id + "radius") * 56
        let x = metrics.center.x + cos(angle) * radius
        let y = metrics.center.y + sin(angle) * radius
        let minX = metrics.padding + metrics.cardSize.width / 2
        let maxX = metrics.bounds.width - metrics.padding - metrics.cardSize.width / 2
        let minY = metrics.padding + metrics.cardSize.height / 2
        let maxY = metrics.bounds.height - metrics.padding - metrics.cardSize.height / 2
        return CGPoint(x: min(max(x, minX), maxX), y: min(max(y, minY), maxY))
    }

    private static func stableUnit(_ text: String) -> CGFloat {
        var hash: UInt64 = 5381
        for scalar in text.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }
        return CGFloat(hash % 10000) / 10000
    }
}

private struct DroidCodeGraphFlowLayoutMetrics {
    let center: CGPoint
    let bounds: CGSize
    let cardSize: CGSize
    let padding: CGFloat
}

private extension CGPoint {
    func clamped(to bounds: CGSize, cardSize: CGSize, padding: CGFloat) -> CGPoint {
        CGPoint(
            x: min(max(x, padding), bounds.width - padding - cardSize.width),
            y: min(max(y, padding), bounds.height - padding - cardSize.height)
        )
    }
}

extension [DroidCodeGraphNode] {
    func uniquedByID() -> [DroidCodeGraphNode] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}
