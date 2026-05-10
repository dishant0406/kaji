import Foundation
import Testing

@testable import Droid

@MainActor
struct DroidBrowserAgentEnvironmentTests {
    @Test
    func keepsRequestedSessionIDWhenBrokerAlreadyExists() throws {
        _ = DroidBrowserControlBroker.shared.ensureStarted(sessionID: "default")
        let values = Dictionary(uniqueKeysWithValues: DroidBrowserAgentEnvironment.variables(
            sessionID: "worktree-session",
            homeDirectory: FileManager.default.temporaryDirectory.path,
            fileManager: .default,
            browserEnabled: true
        ).map { ($0.key, $0.value) })

        #expect(values["DROID_BROWSER_SESSION_ID"] == "worktree-session")
    }

    @Test
    func returnsNoValuesWhenBrowserDisabled() throws {
        let values = DroidBrowserAgentEnvironment.variables(
            sessionID: "worktree-session",
            homeDirectory: FileManager.default.temporaryDirectory.path,
            fileManager: .default,
            browserEnabled: false
        )

        #expect(values.isEmpty)
    }
}
