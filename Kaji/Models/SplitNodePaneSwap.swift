import Foundation

@MainActor
extension SplitNode {
    func swapAreas(_ sourceAreaID: UUID, _ targetAreaID: UUID) -> Bool {
        guard let sourcePath = pathToArea(id: sourceAreaID) else { return false }
        guard let targetPath = pathToArea(id: targetAreaID) else { return false }
        guard let sourceNode = node(at: sourcePath) else { return false }
        guard let targetNode = node(at: targetPath) else { return false }
        guard replaceNode(at: sourcePath, with: targetNode) else { return false }
        guard replaceNode(at: targetPath, with: sourceNode) else { return false }
        return true
    }

    private func pathToArea(id areaID: UUID) -> [SplitNodePathSide]? {
        switch self {
        case let .tabArea(area):
            return area.id == areaID ? [] : nil
        case let .split(branch):
            if let path = branch.first.pathToArea(id: areaID) {
                return [.first] + path
            }
            if let path = branch.second.pathToArea(id: areaID) {
                return [.second] + path
            }
            return nil
        }
    }

    private func node(at path: [SplitNodePathSide]) -> SplitNode? {
        guard let side = path.first else { return self }
        guard case let .split(branch) = self else { return nil }
        let child = side == .first ? branch.first : branch.second
        return child.node(at: Array(path.dropFirst()))
    }

    @discardableResult
    private func replaceNode(at path: [SplitNodePathSide], with replacement: SplitNode) -> Bool {
        guard let side = path.first else { return false }
        guard case let .split(branch) = self else { return false }
        let remainingPath = Array(path.dropFirst())
        guard !remainingPath.isEmpty else {
            switch side {
            case .first:
                branch.first = replacement
                return true
            case .second:
                branch.second = replacement
                return true
            }
        }
        let child = side == .first ? branch.first : branch.second
        return child.replaceNode(at: remainingPath, with: replacement)
    }
}

private enum SplitNodePathSide {
    case first
    case second
}
