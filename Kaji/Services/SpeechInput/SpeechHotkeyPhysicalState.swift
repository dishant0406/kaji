import AppKit
import CoreGraphics
import Foundation

enum SpeechHotkeyPhysicalState {
    static func isPressed(_ combo: KeyCombo) -> Bool {
        guard let keyCode = combo.physicalKeyCode else {
            return combo.requiredModifiersArePressed(in: NSEvent.modifierFlags)
        }
        let keyDown = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
        return keyDown && combo.requiredModifiersArePressed(in: NSEvent.modifierFlags)
    }
}
