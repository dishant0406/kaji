import Foundation

enum TerminalEnvironmentPolicy {
    static func applyToProcessEnvironment() {
        for key in disabledColorKeys {
            unsetenv(key)
        }
    }

    static func sanitizedEnvironment(
        from environment: [String: String]
    ) -> [String: String] {
        environment.filter { !disabledColorKeys.contains($0.key) }
    }

    private static let disabledColorKeys: Set<String> = [
        "NO_COLOR",
    ]
}
