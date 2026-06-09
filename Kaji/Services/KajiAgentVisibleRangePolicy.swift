import CoreGraphics

struct KajiAgentVisibleLayout: Equatable {
    let range: Range<Int>
    let topSpacerHeight: CGFloat
    let bottomSpacerHeight: CGFloat
    let totalHeight: CGFloat
}

enum KajiAgentVisibleRangePolicy {
    static func layout(
        heights: [CGFloat],
        scrollOffset: CGFloat,
        viewportHeight: CGFloat,
        overscanScreens: CGFloat = 2
    ) -> KajiAgentVisibleLayout {
        guard !heights.isEmpty else {
            return KajiAgentVisibleLayout(range: 0 ..< 0, topSpacerHeight: 0, bottomSpacerHeight: 0, totalHeight: 0)
        }

        let totalHeight = heights.reduce(0, +)
        let overscan = max(viewportHeight, 1) * max(overscanScreens, 0)
        let startY = max(0, scrollOffset - overscan)
        let endY = min(totalHeight, scrollOffset + viewportHeight + overscan)
        var y: CGFloat = 0
        var lower = 0
        var upper = heights.count

        for index in heights.indices {
            let nextY = y + heights[index]
            if nextY >= startY {
                lower = index
                break
            }
            y = nextY
        }

        y = 0
        for index in heights.indices {
            y += heights[index]
            if y > endY {
                upper = min(heights.count, index + 1)
                break
            }
        }

        let top = heights.prefix(lower).reduce(0, +)
        let visible = heights[lower ..< upper].reduce(0, +)
        return KajiAgentVisibleLayout(
            range: lower ..< upper,
            topSpacerHeight: top,
            bottomSpacerHeight: max(0, totalHeight - top - visible),
            totalHeight: totalHeight
        )
    }
}
