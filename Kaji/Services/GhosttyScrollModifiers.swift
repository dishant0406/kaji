import AppKit
import GhosttyKit

struct GhosttyScrollModifiers: Equatable {
    let rawValue: ghostty_input_scroll_mods_t

    init(precision: Bool, momentum: ghostty_input_mouse_momentum_e) {
        var value: ghostty_input_scroll_mods_t = 0
        if precision {
            value |= 1
        }
        value |= ghostty_input_scroll_mods_t(momentum.rawValue) << 1
        rawValue = value
    }

    init(precision: Bool, phase: NSEvent.Phase) {
        self.init(precision: precision, momentum: Self.momentum(from: phase))
    }

    static func momentum(from phase: NSEvent.Phase) -> ghostty_input_mouse_momentum_e {
        if phase.contains(.began) { return GHOSTTY_MOUSE_MOMENTUM_BEGAN }
        if phase.contains(.stationary) { return GHOSTTY_MOUSE_MOMENTUM_STATIONARY }
        if phase.contains(.changed) { return GHOSTTY_MOUSE_MOMENTUM_CHANGED }
        if phase.contains(.ended) { return GHOSTTY_MOUSE_MOMENTUM_ENDED }
        if phase.contains(.cancelled) { return GHOSTTY_MOUSE_MOMENTUM_CANCELLED }
        if phase.contains(.mayBegin) { return GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN }
        return GHOSTTY_MOUSE_MOMENTUM_NONE
    }
}
