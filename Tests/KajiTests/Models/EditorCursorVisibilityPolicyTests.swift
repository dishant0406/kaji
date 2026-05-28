import Testing
import CoreGraphics

@testable import Kaji

@Suite("EditorCursorVisibilityPolicy")
struct EditorCursorVisibilityPolicyTests {
    @Test("keeps scroll unchanged when cursor is fully visible")
    func visibleCursor() {
        #expect(EditorCursorVisibilityPolicy.adjustedScrollY(
            cursorTop: 120,
            cursorBottom: 140,
            visibleMinY: 100,
            visibleHeight: 80
        ) == nil)
    }

    @Test("scrolls down to reveal cursor bottom")
    func cursorBelowVisibleRect() {
        #expect(EditorCursorVisibilityPolicy.adjustedScrollY(
            cursorTop: 190,
            cursorBottom: 210,
            visibleMinY: 100,
            visibleHeight: 80
        ) == 130)
    }

    @Test("scrolls up to reveal cursor top")
    func cursorAboveVisibleRect() {
        #expect(EditorCursorVisibilityPolicy.adjustedScrollY(
            cursorTop: 70,
            cursorBottom: 90,
            visibleMinY: 100,
            visibleHeight: 80
        ) == 70)
    }

    @Test("keeps scroll origin unchanged when cursor rect is visible")
    func visibleCursorOrigin() {
        #expect(EditorCursorVisibilityPolicy.adjustedScrollOrigin(
            cursorRect: CGRect(x: 120, y: 120, width: 10, height: 20),
            visibleRect: CGRect(x: 100, y: 100, width: 80, height: 80),
            documentSize: CGSize(width: 400, height: 400)
        ) == nil)
    }

    @Test("scrolls horizontally and vertically to reveal cursor rect")
    func cursorOriginOutsideVisibleRect() {
        #expect(EditorCursorVisibilityPolicy.adjustedScrollOrigin(
            cursorRect: CGRect(x: 210, y: 190, width: 20, height: 25),
            visibleRect: CGRect(x: 100, y: 100, width: 80, height: 80),
            documentSize: CGSize(width: 400, height: 400)
        ) == CGPoint(x: 150, y: 135))
    }

    @Test("clamps scroll origin to document bounds")
    func clampsCursorOrigin() {
        #expect(EditorCursorVisibilityPolicy.adjustedScrollOrigin(
            cursorRect: CGRect(x: 900, y: 900, width: 50, height: 50),
            visibleRect: CGRect(x: 100, y: 100, width: 80, height: 80),
            documentSize: CGSize(width: 200, height: 210)
        ) == CGPoint(x: 120, y: 130))
    }
}
