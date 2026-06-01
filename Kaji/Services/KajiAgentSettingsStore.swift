import Foundation

@MainActor
@Observable
final class KajiAgentSettingsStore {
    static let shared = KajiAgentSettingsStore()
    static let permissionModeKey = "kaji.agent.permissionMode"

    private let defaults: UserDefaults

    var permissionMode: String {
        didSet {
            if KajiAgentPermissionMode(rawValue: permissionMode) == nil {
                permissionMode = KajiAgentPermissionMode.readAllow.rawValue
            }
            defaults.set(permissionMode, forKey: Self.permissionModeKey)
        }
    }

    var selectedPermissionMode: KajiAgentPermissionMode {
        KajiAgentPermissionMode(rawValue: permissionMode) ?? .readAllow
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.permissionModeKey)
        permissionMode = KajiAgentPermissionMode(rawValue: stored ?? "")?.rawValue ?? KajiAgentPermissionMode.readAllow.rawValue
    }
}
