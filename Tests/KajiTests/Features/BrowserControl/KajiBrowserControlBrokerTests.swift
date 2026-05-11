import Foundation
import Testing

@testable import Kaji

struct KajiBrowserControlBrokerTests {
    @Test
    func startsOnRealLocalPort() throws {
        let sessionFile = KajiBrowserSessionEnvironmentStore.fileURL()
        let originalData = try? Data(contentsOf: sessionFile)
        defer { restore(data: originalData, to: sessionFile) }

        let state = try #require(KajiBrowserControlBroker.shared.ensureStarted(sessionID: "test"))

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
