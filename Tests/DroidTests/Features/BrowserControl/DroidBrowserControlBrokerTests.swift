import Foundation
import Testing

@testable import Droid

struct DroidBrowserControlBrokerTests {
    @Test
    func startsOnRealLocalPort() throws {
        let sessionFile = DroidBrowserSessionEnvironmentStore.fileURL()
        let originalData = try? Data(contentsOf: sessionFile)
        defer { restore(data: originalData, to: sessionFile) }

        let state = try #require(DroidBrowserControlBroker.shared.ensureStarted(sessionID: "test"))

        #expect(state.port > 0)
        #expect(!state.brokerURL.hasSuffix(":0"))
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
