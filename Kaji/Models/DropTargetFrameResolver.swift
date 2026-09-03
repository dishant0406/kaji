import CoreGraphics
import Foundation

enum DropTargetFrameResolver {
    struct Match {
        let areaID: UUID
        let frame: CGRect
        let metric: CGFloat
    }

    static func containingMatch(for point: CGPoint, in frames: [UUID: CGRect]) -> Match? {
        var bestMatch: Match?

        for (areaID, frame) in frames {
            guard frame.contains(point) else { continue }
            let dx = point.x - frame.midX
            let dy = point.y - frame.midY
            let metric = dx * dx + dy * dy

            guard bestMatch?.metric ?? .greatestFiniteMagnitude > metric else { continue }
            bestMatch = Match(areaID: areaID, frame: frame, metric: metric)
        }

        return bestMatch
    }

    static func nearestMatch(for point: CGPoint, in frames: [UUID: CGRect], tolerance: CGFloat) -> Match? {
        var bestMatch: Match?

        for (areaID, frame) in frames {
            let metric = distance(from: point, to: frame)
            guard metric <= tolerance else { continue }
            guard bestMatch?.metric ?? .greatestFiniteMagnitude > metric else { continue }
            bestMatch = Match(areaID: areaID, frame: frame, metric: metric)
        }

        return bestMatch
    }

    static func clamped(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    static func zone(for point: CGPoint, in rect: CGRect) -> DropZone {
        guard rect.width > 0, rect.height > 0 else { return .center }

        let relX = (point.x - rect.minX) / rect.width
        let relY = (point.y - rect.minY) / rect.height
        let edgeThreshold: CGFloat = 0.3

        if relX < edgeThreshold {
            return .left
        }
        if relX > 1 - edgeThreshold {
            return .right
        }
        if relY < edgeThreshold {
            return .top
        }
        if relY > 1 - edgeThreshold {
            return .bottom
        }
        return .center
    }

    static func edgeZone(for point: CGPoint, in rect: CGRect) -> DropZone? {
        guard rect.width > 0, rect.height > 0 else { return nil }

        let leftInset = point.x - rect.minX
        let rightInset = rect.maxX - point.x
        let topInset = point.y - rect.minY
        let bottomInset = rect.maxY - point.y
        let threshold = min(max(min(rect.width, rect.height) * 0.28, 28), 72)

        let candidates: [(DropZone, CGFloat)] = [
            (.left, leftInset),
            (.right, rightInset),
            (.top, topInset),
            (.bottom, bottomInset),
        ]

        guard let nearest = candidates.min(by: { $0.1 < $1.1 }), nearest.1 <= threshold else { return nil }
        return nearest.0
    }

    static func nearestEdgeZone(for point: CGPoint, in rect: CGRect) -> DropZone {
        let candidates: [(DropZone, CGFloat)] = [
            (.left, point.x - rect.minX),
            (.right, rect.maxX - point.x),
            (.top, point.y - rect.minY),
            (.bottom, rect.maxY - point.y),
        ]
        return candidates.min(by: { $0.1 < $1.1 })?.0 ?? .right
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, max(0, point.x - rect.maxX))
        let dy = max(rect.minY - point.y, max(0, point.y - rect.maxY))
        return hypot(dx, dy)
    }
}
