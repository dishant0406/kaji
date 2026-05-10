import Testing

@testable import Droid

struct DroidBrowserControlBrokerTests {
    @Test
    func startsOnRealLocalPort() throws {
        let state = try #require(DroidBrowserControlBroker.shared.ensureStarted(sessionID: "test"))

        #expect(state.port > 0)
        #expect(!state.brokerURL.hasSuffix(":0"))
    }
}
