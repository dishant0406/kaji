import Testing

@testable import Kaji

struct KajiCursorTests {
    @Test
    func exposesStableSemanticCursorNames() {
        #expect(KajiCursor.pointer.name == "pointer")
        #expect(KajiCursor.text.name == "text")
        #expect(KajiCursor.disabled.name == "disabled")
        #expect(KajiCursor.resizeLeftRight.name == "resizeLeftRight")
        #expect(KajiCursor.resizeUpDown.name == "resizeUpDown")
    }
}
