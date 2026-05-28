import CoreGraphics

enum EditorViewportLayoutPolicy {
    static func shouldMeasureTextLayout(isScrollDrivenRefresh: Bool) -> Bool {
        !isScrollDrivenRefresh
    }

    static func minimumViewportWidth(
        scrollContentWidth: CGFloat,
        currentTextWidth: CGFloat,
        preservesCurrentWidth: Bool
    ) -> CGFloat {
        guard preservesCurrentWidth else { return scrollContentWidth }
        return max(scrollContentWidth, currentTextWidth)
    }
}
