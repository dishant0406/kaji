import Foundation

/// Host-side cursor blink phase. The terminal core reports cursor position and
/// style; blinking is a presentation concern owned by the host, matching the
/// GPUI app's 530ms cadence and its hold-solid-while-typing behavior.
struct TerminalCursorBlinkPhase {
    static let interval: TimeInterval = 0.53

    private(set) var isVisible = true
    private var lastToggleAt: Date?
    private var lastInputAt: Date?

    /// Holds the cursor solid for one blink interval after input so sustained
    /// typing doesn't fight the toggle. Matches xterm and the GPUI app.
    mutating func noteInput(at now: Date = Date()) {
        lastInputAt = now
        isVisible = true
    }

    /// Advances the blink phase from a refresh tick. Returns `true` when the
    /// cursor visibility changed and the cursor row needs a repaint.
    mutating func tick(blinkEnabled: Bool, now: Date = Date()) -> Bool {
        guard blinkEnabled else {
            return makeVisible()
        }

        if let lastInputAt, now.timeIntervalSince(lastInputAt) < Self.interval {
            lastToggleAt = now
            return makeVisible()
        }

        guard let lastToggleAt else {
            self.lastToggleAt = now
            return false
        }
        guard now.timeIntervalSince(lastToggleAt) >= Self.interval else {
            return false
        }

        self.lastToggleAt = now
        isVisible.toggle()
        return true
    }

    private mutating func makeVisible() -> Bool {
        guard !isVisible else {
            return false
        }
        isVisible = true
        return true
    }
}
