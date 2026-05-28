import CoreGraphics

enum EditorCursorVisibilityPolicy {
    static func adjustedScrollY(
        cursorTop: CGFloat,
        cursorBottom: CGFloat,
        visibleMinY: CGFloat,
        visibleHeight: CGFloat
    ) -> CGFloat? {
        let visibleMaxY = visibleMinY + visibleHeight
        if cursorBottom > visibleMaxY {
            return cursorBottom - visibleHeight
        }
        if cursorTop < visibleMinY {
            return cursorTop
        }
        return nil
    }

    static func adjustedScrollOrigin(
        cursorRect: CGRect,
        visibleRect: CGRect,
        documentSize: CGSize
    ) -> CGPoint? {
        let maxScrollX = max(0, documentSize.width - visibleRect.width)
        let maxScrollY = max(0, documentSize.height - visibleRect.height)
        var newOrigin = visibleRect.origin

        if cursorRect.maxX > visibleRect.maxX {
            newOrigin.x = min(maxScrollX, max(0, cursorRect.maxX - visibleRect.width))
        } else if cursorRect.minX < visibleRect.minX {
            newOrigin.x = min(maxScrollX, max(0, cursorRect.minX))
        }

        if cursorRect.maxY > visibleRect.maxY {
            newOrigin.y = min(maxScrollY, max(0, cursorRect.maxY - visibleRect.height))
        } else if cursorRect.minY < visibleRect.minY {
            newOrigin.y = min(maxScrollY, max(0, cursorRect.minY))
        }

        return newOrigin == visibleRect.origin ? nil : newOrigin
    }
}
