import Testing

@testable import Kaji

struct KajiAgentRuntimeErrorGateTests {
    @Test
    func showsOnlyFirstThreeDecodeErrors() {
        var gate = KajiAgentRuntimeErrorGate()
        let first = gate.shouldShow("Failed to decode runtime event A")
        let second = gate.shouldShow("Failed to decode runtime event B")
        let third = gate.shouldShow("Failed to decode runtime event C")
        let fourth = gate.shouldShow("Failed to decode runtime event D")

        #expect(first)
        #expect(second)
        #expect(third)
        #expect(!fourth)
    }

    @Test
    func resetAllowsDecodeErrorsAgain() {
        var gate = KajiAgentRuntimeErrorGate()

        for _ in 0 ..< 4 { _ = gate.shouldShow("Failed to decode runtime event") }
        gate.reset()
        let afterReset = gate.shouldShow("Failed to decode runtime event again")

        #expect(afterReset)
    }

    @Test
    func alwaysShowsOtherRuntimeErrors() {
        var gate = KajiAgentRuntimeErrorGate()

        for _ in 0 ..< 10 {
            let visible = gate.shouldShow("Kaji runtime is missing or Bun is unavailable.")
            #expect(visible)
        }
    }
}
