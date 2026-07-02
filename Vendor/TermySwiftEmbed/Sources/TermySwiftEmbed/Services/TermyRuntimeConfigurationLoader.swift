import Foundation
import TermyKit

enum TermyRuntimeConfigurationLoader {
    static func load(source: TermyConfigurationSource) throws -> TermyRuntimeConfiguration {
        let config = try LibTermyTerminal.loadConfig(source)
        defer {
            if let config {
                _ = termy_config_free(config)
            }
        }
        guard let config else {
            return .default
        }

        let activeLimit = TermyRuntimeConfiguration.clampedScrollbackHistory(
            termy_config_runtime_scrollback_history(config)
        )
        let inactiveLimit = try inactiveTabScrollback(config: config, activeLimit: activeLimit)
        return TermyRuntimeConfiguration(
            scrollbackHistory: activeLimit,
            inactiveTabScrollback: inactiveLimit
        )
    }

    static func loadOrDefault(source: TermyConfigurationSource) -> TermyRuntimeConfiguration {
        (try? load(source: source)) ?? .default
    }

    private static func inactiveTabScrollback(config: OpaquePointer, activeLimit: Int) throws -> Int? {
        var enabled = false
        var value = 0
        try TermyFfiBridge.requireOK(
            "termy_config_runtime_inactive_tab_scrollback",
            termy_config_runtime_inactive_tab_scrollback(config, &enabled, &value)
        )
        guard enabled else {
            return nil
        }
        return TermyRuntimeConfiguration.clampedInactiveTabScrollback(value, activeLimit: activeLimit)
    }
}
