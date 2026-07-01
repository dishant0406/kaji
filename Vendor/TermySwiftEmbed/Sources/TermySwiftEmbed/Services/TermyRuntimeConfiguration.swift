import Foundation

struct TermyRuntimeConfiguration: Equatable {
    var native = TermyNativeRuntimeConfiguration()
    var scrollbackHistory = 10000
    var inactiveTabScrollback: Int?

    static let `default` = TermyRuntimeConfiguration()
}

struct TermyNativeRuntimeConfiguration: Equatable {
    var progressIndicatorEnabled = true
    var showDebugOverlay = false
    var shellIntegrationEnabled = true
}
