import Foundation
import Testing

@testable import Kaji

@MainActor
struct KajiBrowserAgentEnvironmentTests {
    @Test
    func keepsRequestedSessionIDWhenBrokerAlreadyExists() throws {
        _ = KajiBrowserControlBroker.shared.ensureStarted(sessionID: "default")
        let values = Dictionary(uniqueKeysWithValues: KajiBrowserAgentEnvironment.variables(
            sessionID: "worktree-session",
            homeDirectory: FileManager.default.temporaryDirectory.path,
            fileManager: .default,
            browserEnabled: true
        ).map { ($0.key, $0.value) })

        #expect(values["KAJI_BROWSER_SESSION_ID"] == "worktree-session")
    }

    @Test
    func returnsNoValuesWhenBrowserDisabled() throws {
        let values = KajiBrowserAgentEnvironment.variables(
            sessionID: "worktree-session",
            homeDirectory: FileManager.default.temporaryDirectory.path,
            fileManager: .default,
            browserEnabled: false,
            unsafeToolsEnabled: true
        )

        #expect(values.isEmpty)
    }

    @Test
    func includesUnsafeToolsEnvironmentWhenEnabled() throws {
        _ = KajiBrowserControlBroker.shared.ensureStarted(sessionID: "unsafe-session")
        let values = Dictionary(uniqueKeysWithValues: KajiBrowserAgentEnvironment.variables(
            sessionID: "unsafe-session",
            homeDirectory: FileManager.default.temporaryDirectory.path,
            fileManager: .default,
            browserEnabled: true,
            unsafeToolsEnabled: true
        ).map { ($0.key, $0.value) })

        #expect(values["KAJI_BROWSER_ALLOW_UNSAFE_TOOLS"] == "1")
    }
}
