import AppKit
import Foundation

struct SpeechHotkeyMatcher {
    let combo: KeyCombo

    func matchesPress(_ event: NSEvent) -> Bool {
        event.type == .keyDown && !event.isARepeat && combo.matches(event: event)
    }

    func matchesRelease(_ event: NSEvent) -> Bool {
        event.type == .keyUp && combo.matchesKey(event: event)
    }
}
