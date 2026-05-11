import CoreGraphics

enum KajiCodeGraphFlowDragMode {
    case canvas(start: CGSize)
    case node(id: String, start: CGSize)
}

extension [KajiCodeGraphNode] {
    func sortedForFlow(selectedNodeID: String?) -> [KajiCodeGraphNode] {
        sorted { left, right in
            if left.id == selectedNodeID { return false }
            if right.id == selectedNodeID { return true }
            return left.degree < right.degree
        }
    }
}

enum KajiCodeGraphScale {
    static func clamped(_ value: CGFloat) -> CGFloat {
        min(2.4, max(0.35, value))
    }
}

extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
