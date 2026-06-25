import Foundation
import Testing

@testable import Kaji

@Suite(.serialized)
struct KajiBrowserControlBrokerTests {
    @Test
    func startsOnRealLocalPort() throws {
        let sessionFile = KajiBrowserSessionEnvironmentStore.fileURL()
        let originalData = try? Data(contentsOf: sessionFile)
        defer {
            KajiBrowserControlBroker.shared.stop()
            restore(data: originalData, to: sessionFile)
        }

        let state = try #require(KajiBrowserControlBroker.shared.ensureStarted(sessionID: "test"))

        #expect(state.port > 0)
        #expect(!state.brokerURL.hasSuffix(":0"))
    }

    @Test
    func updatesPublishedSessionWhenBrokerAlreadyRuns() throws {
        let sessionFile = KajiBrowserSessionEnvironmentStore.fileURL()
        let originalData = try? Data(contentsOf: sessionFile)
        defer {
            KajiBrowserControlBroker.shared.stop()
            restore(data: originalData, to: sessionFile)
        }

        let first = try #require(KajiBrowserControlBroker.shared.ensureStarted(sessionID: "first"))
        let second = try #require(KajiBrowserControlBroker.shared.ensureStarted(sessionID: "second"))
        let data = try Data(contentsOf: sessionFile)
        let values = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(first.port == second.port)
        #expect(first.token == second.token)
        #expect(second.sessionID == "second")
        #expect(values["sessionId"] as? String == "second")
    }

    @Test
    @MainActor
    func browserSessionRegistrationPublishesBrokerSession() throws {
        let sessionFile = KajiBrowserSessionEnvironmentStore.fileURL()
        let originalData = try? Data(contentsOf: sessionFile)
        defer {
            KajiBrowserControlBroker.shared.stop()
            restore(data: originalData, to: sessionFile)
        }

        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        let session = BrowserSession(key: key, state: BrowserPaneState(projectPath: "/tmp/test"))

        session.registerControl {}

        let data = try Data(contentsOf: sessionFile)
        let values = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(values["sessionId"] as? String == key.worktreeID.uuidString)
        #expect((values["brokerUrl"] as? String)?.hasPrefix("http://127.0.0.1:") == true)
        #expect((values["token"] as? String)?.isEmpty == false)
    }

    private func restore(data: Data?, to file: URL) {
        guard let data else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
