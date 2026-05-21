import CoreGraphics

protocol ReorderableAxis {
    static func project(point: CGPoint) -> CGFloat
    static func project(size: CGSize) -> CGFloat
    static func offset(_ value: CGFloat) -> CGSize
    static func position(in frame: CGRect) -> ReorderableItemPosition
}

struct ReorderableHorizontalAxis: ReorderableAxis {
    static func project(point: CGPoint) -> CGFloat { point.x }
    static func project(size: CGSize) -> CGFloat { size.width }
    static func offset(_ value: CGFloat) -> CGSize { CGSize(width: value, height: 0) }
    static func position(in frame: CGRect) -> ReorderableItemPosition {
        ReorderableItemPosition(min: frame.minX, max: frame.maxX)
    }
}

struct ReorderableVerticalAxis: ReorderableAxis {
    static func project(point: CGPoint) -> CGFloat { point.y }
    static func project(size: CGSize) -> CGFloat { size.height }
    static func offset(_ value: CGFloat) -> CGSize { CGSize(width: 0, height: value) }
    static func position(in frame: CGRect) -> ReorderableItemPosition {
        ReorderableItemPosition(min: frame.minY, max: frame.maxY)
    }
}

struct ReorderableItemPosition: Equatable {
    let min: CGFloat
    let max: CGFloat

    var span: CGFloat { max - min }
    var midpoint: CGFloat { min + span / 2 }

    func contains(_ value: CGFloat) -> Bool {
        min <= value && value <= max
    }
}
