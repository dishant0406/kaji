import Foundation

enum TerminalShellIntegrationMode: String, CaseIterable, Identifiable {
    case detect = "Detect"
    case disabled = "Disabled"
    case bash = "Bash"
    case fish = "Fish"
    case zsh = "Zsh"
    case nushell = "Nushell"
    case elvish = "Elvish"

    var id: String { rawValue }

    var termyValue: String {
        switch self {
        case .detect: "detect"
        case .disabled: "none"
        case .bash: "bash"
        case .fish: "fish"
        case .zsh: "zsh"
        case .nushell: "nushell"
        case .elvish: "elvish"
        }
    }
}

enum TerminalScrollbackProfile: String, CaseIterable, Identifiable {
    case compact = "Compact"
    case balanced = "Balanced"
    case legacy = "Legacy"
    case custom = "Custom"

    static let defaultLimit = 10000
    static let minimumCustomLimit = 100
    static let maximumCustomLimit = 100_000
    private static let maximumInactiveLimit = 10000

    var id: String { rawValue }

    func limit(customValue: Int) -> Int {
        switch self {
        case .compact: 1000
        case .balanced: Self.defaultLimit
        case .legacy: 50000
        case .custom: min(max(customValue, Self.minimumCustomLimit), Self.maximumCustomLimit)
        }
    }

    func inactiveLimit(customValue: Int) -> Int {
        min(max(limit(customValue: customValue) / 10, 250), Self.maximumInactiveLimit)
    }
}

enum TerminalScrollSpeedProfile: String, CaseIterable, Identifiable {
    case native = "Native"
    case fast = "Fast"
    case veryFast = "Very Fast"

    var id: String { rawValue }

    var termyValue: String {
        switch self {
        case .native: "precision:1,discrete:3"
        case .fast: "precision:3,discrete:5"
        case .veryFast: "precision:5,discrete:8"
        }
    }
}

enum TerminalImageStorageProfile: String, CaseIterable, Identifiable {
    case disabled = "Disabled"
    case lean = "Lean"
    case balanced = "Balanced"
    case high = "High"

    var id: String { rawValue }

    var byteLimit: Int {
        switch self {
        case .disabled: 0
        case .lean: 64 * 1024 * 1024
        case .balanced: 320 * 1024 * 1024
        case .high: 512 * 1024 * 1024
        }
    }
}

enum TerminalClipboardAccess: String, CaseIterable, Identifiable {
    case ask = "Ask"
    case allow = "Allow"
    case deny = "Deny"

    var id: String { rawValue }

    var termyValue: String { rawValue.lowercased() }
}

enum TerminalOptionAsAltMode: String, CaseIterable, Identifiable {
    case always = "Alt"
    case never = "Unicode"
    case left = "Left Alt"
    case right = "Right Alt"

    var id: String { rawValue }

    var termyValue: String {
        switch self {
        case .always: "true"
        case .never: "false"
        case .left: "left"
        case .right: "right"
        }
    }
}

enum TerminalCursorStyle: String, CaseIterable, Identifiable {
    case line = "Line"
    case block = "Block"

    var id: String { rawValue }

    var termyValue: String {
        switch self {
        case .line: "line"
        case .block: "block"
        }
    }
}

enum TerminalGlassBlurMode: String, CaseIterable, Identifiable {
    case regular = "Regular Glass"
    case clear = "Clear Glass"

    var id: String { rawValue }

    var termyValue: String {
        switch self {
        case .regular: "macos-glass-regular"
        case .clear: "macos-glass-clear"
        }
    }
}
