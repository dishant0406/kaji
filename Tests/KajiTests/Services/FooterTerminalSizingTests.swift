import Testing

@testable import Kaji

struct FooterTerminalSizingTests {
    @Test
    func resolvesPercentSize() {
        #expect(FooterTerminalSizing.height(from: "40%", screenHeight: 1000) == 400)
    }

    @Test
    func clampsLargeSize() {
        #expect(FooterTerminalSizing.height(from: "90%", screenHeight: 1000) == 720)
    }

    @Test
    func resolvesPixelSize() {
        #expect(FooterTerminalSizing.height(from: "420px", screenHeight: 1000) == 420)
    }
}
