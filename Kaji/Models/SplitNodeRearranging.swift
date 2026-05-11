import Foundation

@MainActor
extension SplitNode {
    func detachingArea(_ areaID: UUID) -> (remaining: SplitNode?, detached: SplitNode?) {
        switch self {
        case let .tabArea(area) where area.id == areaID:
            return (nil, self)
        case .tabArea:
            return (self, nil)
        case let .split(branch):
            let first = branch.first.detachingArea(areaID)
            if let detached = first.detached {
                if let remaining = first.remaining {
                    branch.first = remaining
                    return (.split(branch), detached)
                }
                return (branch.second, detached)
            }

            let second = branch.second.detachingArea(areaID)
            if let detached = second.detached {
                if let remaining = second.remaining {
                    branch.second = remaining
                    return (.split(branch), detached)
                }
                return (branch.first, detached)
            }

            return (.split(branch), nil)
        }
    }

    func insertingArea(
        _ node: SplitNode,
        beside targetAreaID: UUID,
        split: SplitPlacement
    ) -> (node: SplitNode, inserted: Bool) {
        switch self {
        case let .tabArea(area) where area.id == targetAreaID:
            let first = split.position == .first ? node : self
            let second = split.position == .first ? self : node
            return (.split(SplitBranch(direction: split.direction, first: first, second: second)), true)
        case .tabArea:
            return (self, false)
        case let .split(branch):
            let first = branch.first.insertingArea(node, beside: targetAreaID, split: split)
            if first.inserted {
                branch.first = first.node
                return (.split(branch), true)
            }

            let second = branch.second.insertingArea(node, beside: targetAreaID, split: split)
            if second.inserted {
                branch.second = second.node
                return (.split(branch), true)
            }

            return (.split(branch), false)
        }
    }
}
