import Foundation

enum PowerAssertionLaunchEnvironment {
    static let ownershipKey = "KAJI_APP_OWNS_POWER_ASSERTIONS"

    static func applyingAppOwnership(
        to environment: [String: String],
        assertionIsActive: Bool
    ) -> [String: String] {
        var environment = environment
        environment[ownershipKey] = assertionIsActive ? "1" : nil
        return environment
    }
}
