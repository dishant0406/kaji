import AppKit
import Carbon.HIToolbox
import SwiftUI

enum ShortcutScope: String, Codable, CaseIterable {
    case global
    case mainWindow
}

struct KeyCombo: Codable, Equatable, Hashable {
    static let supportedModifierMask: NSEvent.ModifierFlags = [.command, .shift, .control, .option]
    static let leftArrowKey = "leftarrow"
    static let rightArrowKey = "rightarrow"
    static let upArrowKey = "uparrow"
    static let downArrowKey = "downarrow"
    static let spaceKey = "space"
    static let returnKey = "return"

    let key: String
    let modifiers: UInt

    init(key: String, modifiers: UInt) {
        self.key = Self.normalized(key: key)
        self.modifiers = Self.normalized(modifiers: modifiers)
    }

    init(
        key: String, command: Bool = false, shift: Bool = false, control: Bool = false,
        option: Bool = false
    ) {
        self.key = Self.normalized(key: key)
        var flags: UInt = 0
        if command {
            flags |= NSEvent.ModifierFlags.command.rawValue
        }
        if shift {
            flags |= NSEvent.ModifierFlags.shift.rawValue
        }
        if control {
            flags |= NSEvent.ModifierFlags.control.rawValue
        }
        if option {
            flags |= NSEvent.ModifierFlags.option.rawValue
        }
        self.modifiers = flags
    }

    var nsModifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(Self.supportedModifierMask)
    }

    var swiftUIKeyEquivalent: KeyEquivalent {
        switch key {
        case "": KeyEquivalent(" ")
        case "[": KeyEquivalent("[")
        case "]": KeyEquivalent("]")
        case ",": KeyEquivalent(",")
        case Self.leftArrowKey: .leftArrow
        case Self.rightArrowKey: .rightArrow
        case Self.upArrowKey: .upArrow
        case Self.downArrowKey: .downArrow
        case Self.spaceKey: KeyEquivalent(" ")
        case Self.returnKey: KeyEquivalent("\r")
        default: KeyEquivalent(Character(key))
        }
    }

    var swiftUIModifiers: SwiftUI.EventModifiers {
        var result: SwiftUI.EventModifiers = []
        let flags = nsModifierFlags
        if flags.contains(.command) {
            result.insert(.command)
        }
        if flags.contains(.shift) {
            result.insert(.shift)
        }
        if flags.contains(.control) {
            result.insert(.control)
        }
        if flags.contains(.option) {
            result.insert(.option)
        }
        return result
    }

    var displayString: String {
        guard !key.isEmpty else { return "Unassigned" }
        var parts = ""
        let flags = nsModifierFlags
        if flags.contains(.control) {
            parts += "⌃"
        }
        if flags.contains(.option) {
            parts += "⌥"
        }
        if flags.contains(.shift) {
            parts += "⇧"
        }
        if flags.contains(.command) {
            parts += "⌘"
        }
        let keyDisplay: String = switch key {
        case Self.leftArrowKey: "←"
        case Self.rightArrowKey: "→"
        case Self.upArrowKey: "↑"
        case Self.downArrowKey: "↓"
        case Self.spaceKey: "Space"
        case Self.returnKey: "Enter"
        default: key.uppercased()
        }
        parts += keyDisplay
        return parts
    }

    func matches(event: NSEvent) -> Bool {
        let eventFlags = event.modifierFlags.intersection(Self.supportedModifierMask).rawValue
        let eventKey = Self.normalized(key: event.charactersIgnoringModifiers ?? "", keyCode: event.keyCode)
        return eventKey == key && eventFlags == modifiers
    }

    func matchesKey(event: NSEvent) -> Bool {
        let eventKey = Self.normalized(key: event.charactersIgnoringModifiers ?? "", keyCode: event.keyCode)
        return eventKey == key
    }

    func requiredModifiersArePressed(in flags: NSEvent.ModifierFlags) -> Bool {
        let active = flags.intersection(Self.supportedModifierMask)
        return nsModifierFlags.isSubset(of: active)
    }

    var physicalKeyCode: UInt16? {
        Self.keyCode(for: key)
    }

    static func normalized(modifiers: UInt) -> UInt {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(supportedModifierMask).rawValue
    }

    static func scalar(for keyCode: UInt16) -> UnicodeScalar? {
        guard let mappedKey = keyName(for: keyCode),
              mappedKey.unicodeScalars.count == 1
        else { return nil }
        return mappedKey.unicodeScalars.first
    }

    static func normalized(key: String, keyCode: UInt16? = nil) -> String {
        if let keyCode, let mappedKey = keyName(for: keyCode) {
            return mappedKey
        }

        let lowercased = key.lowercased()
        if lowercased == leftArrowKey || lowercased == rightArrowKey || lowercased == upArrowKey || lowercased == downArrowKey
            || lowercased == spaceKey || lowercased == returnKey
        {
            return lowercased
        }

        guard let scalar = lowercased.unicodeScalars.first, lowercased.unicodeScalars.count == 1 else {
            return lowercased
        }

        switch Int(scalar.value) {
        case NSLeftArrowFunctionKey: return leftArrowKey
        case NSRightArrowFunctionKey: return rightArrowKey
        case NSUpArrowFunctionKey: return upArrowKey
        case NSDownArrowFunctionKey: return downArrowKey
        default: return lowercased
        }
    }
}
