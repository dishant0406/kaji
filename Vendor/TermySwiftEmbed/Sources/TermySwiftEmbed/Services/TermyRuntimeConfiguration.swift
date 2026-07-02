import Foundation

struct TermyRuntimeConfiguration: Equatable {
    var native = TermyNativeRuntimeConfiguration()
    var scrollbackHistory = Self.defaultScrollbackHistory
    var inactiveTabScrollback: Int?

    static let `default` = TermyRuntimeConfiguration()
    static let defaultScrollbackHistory = 10000
    static let maximumScrollbackHistory = 100_000
    static let maximumInactiveTabScrollback = 10000

    static func clampedScrollbackHistory(_ value: Int) -> Int {
        min(max(value, 0), maximumScrollbackHistory)
    }

    static func clampedInactiveTabScrollback(_ value: Int, activeLimit: Int) -> Int {
        min(max(value, 0), min(activeLimit, maximumInactiveTabScrollback))
    }
}

struct TermyNativeRuntimeConfiguration: Equatable {
    var progressIndicatorEnabled = true
    var showDebugOverlay = false
    var shellIntegrationEnabled = true
}
