import AppKit
import GhosttyKit
import Testing

@testable import Kaji

@Suite("GhosttyScrollModifiers")
struct GhosttyScrollModifiersTests {
    @Test("packs precision and momentum bits")
    func packsPrecisionAndMomentumBits() {
        let mods = GhosttyScrollModifiers(
            precision: true,
            momentum: GHOSTTY_MOUSE_MOMENTUM_CHANGED
        )

        #expect(mods.rawValue == 7)
    }

    @Test("maps AppKit momentum phases")
    func mapsAppKitMomentumPhases() {
        #expect(GhosttyScrollModifiers.momentum(from: .began) == GHOSTTY_MOUSE_MOMENTUM_BEGAN)
        #expect(GhosttyScrollModifiers.momentum(from: .stationary) == GHOSTTY_MOUSE_MOMENTUM_STATIONARY)
        #expect(GhosttyScrollModifiers.momentum(from: .changed) == GHOSTTY_MOUSE_MOMENTUM_CHANGED)
        #expect(GhosttyScrollModifiers.momentum(from: .ended) == GHOSTTY_MOUSE_MOMENTUM_ENDED)
        #expect(GhosttyScrollModifiers.momentum(from: .cancelled) == GHOSTTY_MOUSE_MOMENTUM_CANCELLED)
        #expect(GhosttyScrollModifiers.momentum(from: .mayBegin) == GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN)
        #expect(GhosttyScrollModifiers.momentum(from: []) == GHOSTTY_MOUSE_MOMENTUM_NONE)
    }
}
