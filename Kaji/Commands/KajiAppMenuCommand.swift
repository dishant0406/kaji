import Foundation

enum KajiAppMenuCommand: CaseIterable {
    case settings
    case openConfiguration
    case reloadConfiguration
    case checkForUpdates

    var title: String {
        switch self {
        case .settings:
            "Settings..."
        case .openConfiguration:
            "Open Configuration..."
        case .reloadConfiguration:
            "Reload Configuration"
        case .checkForUpdates:
            "Check for Updates..."
        }
    }
}
