import Foundation

enum PaneResizeCommand {
    case wider
    case narrower
    case taller
    case shorter

    var axis: SplitDirection {
        switch self {
        case .wider,
             .narrower:
            .horizontal
        case .taller,
             .shorter:
            .vertical
        }
    }
}

enum PaneDirectionCommand {
    case left
    case right
    case up
    case down

    var focusDirection: FocusReducer.Direction {
        switch self {
        case .left: .left
        case .right: .right
        case .up: .up
        case .down: .down
        }
    }

    var splitPlacement: SplitPlacement {
        switch self {
        case .left:
            SplitPlacement(direction: .horizontal, position: .first)
        case .right:
            SplitPlacement(direction: .horizontal, position: .second)
        case .up:
            SplitPlacement(direction: .vertical, position: .first)
        case .down:
            SplitPlacement(direction: .vertical, position: .second)
        }
    }
}
