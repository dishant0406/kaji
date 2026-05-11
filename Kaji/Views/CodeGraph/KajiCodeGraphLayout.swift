import CoreGraphics

struct KajiCodeGraphLayout {
    let positions: [String: CGPoint]

    init(document: KajiCodeGraphDocument, size: CGSize, nodeOffsets: [String: CGSize] = [:]) {
        let center = CGPoint(x: max(size.width, 300) / 2, y: max(size.height, 260) / 2)
        let nodes = Array(document.nodes.prefix(1800))
        let grouped = Dictionary(grouping: nodes) { $0.community ?? -1 }
        var result: [String: CGPoint] = [:]
        let communityKeys = grouped.keys.sorted()
        let outerRadius = max(80, min(size.width, size.height) * 0.34)
        for (communityIndex, key) in communityKeys.enumerated() {
            let communityAngle = CGFloat(communityIndex) / CGFloat(max(communityKeys.count, 1)) * .pi * 2
            let communityCenter = CGPoint(
                x: center.x + cos(communityAngle) * outerRadius * 0.48,
                y: center.y + sin(communityAngle) * outerRadius * 0.48
            )
            Self.placeMembers(grouped[key] ?? [], center: communityCenter, result: &result)
        }
        positions = result.reduce(into: [:]) { output, entry in
            let offset = nodeOffsets[entry.key] ?? .zero
            output[entry.key] = CGPoint(x: entry.value.x + offset.width, y: entry.value.y + offset.height)
        }
    }

    func nearestNode(to point: CGPoint, maxDistance: CGFloat) -> String? {
        let nearest = positions.min { lhs, rhs in
            lhs.value.distance(to: point) < rhs.value.distance(to: point)
        }
        guard let nearest, nearest.value.distance(to: point) <= maxDistance else { return nil }
        return nearest.key
    }

    private static func placeMembers(_ members: [KajiCodeGraphNode], center: CGPoint, result: inout [String: CGPoint]) {
        let sortedMembers = members.sorted { $0.degree > $1.degree }
        let radius = max(28, CGFloat(sortedMembers.count) * 3.8)
        for (index, node) in sortedMembers.enumerated() {
            let angle = CGFloat(index) / CGFloat(max(sortedMembers.count, 1)) * .pi * 2
            let ring = radius + CGFloat(index % 4) * 10
            result[node.id] = CGPoint(
                x: center.x + cos(angle) * ring,
                y: center.y + sin(angle) * ring
            )
        }
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}
