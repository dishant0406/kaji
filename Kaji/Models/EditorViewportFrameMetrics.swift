import CoreGraphics

struct EditorViewportFrameMetrics: Equatable {
    let viewportWidth: CGFloat
    let contentHeight: CGFloat

    static func make(
        usedTextSize: CGSize?,
        minimumWidth: CGFloat,
        estimatedHeight: CGFloat,
        horizontalPadding: CGFloat,
        verticalInset: CGFloat
    ) -> EditorViewportFrameMetrics {
        guard let usedTextSize else {
            return EditorViewportFrameMetrics(
                viewportWidth: minimumWidth,
                contentHeight: max(estimatedHeight, 100)
            )
        }

        return EditorViewportFrameMetrics(
            viewportWidth: max(minimumWidth, ceil(usedTextSize.width + horizontalPadding)),
            contentHeight: max(estimatedHeight, ceil(usedTextSize.height + verticalInset), 100)
        )
    }
}
