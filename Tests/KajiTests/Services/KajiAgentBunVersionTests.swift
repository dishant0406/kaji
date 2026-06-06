import Testing

@testable import Kaji

struct KajiAgentBunVersionTests {
    @Test
    func supportsMinimumRuntimeVersion() {
        #expect(!KajiAgentBunVersion("1.3.13").supportsKajiAgentRuntime)
        #expect(KajiAgentBunVersion("1.3.14").supportsKajiAgentRuntime)
        #expect(KajiAgentBunVersion("1.4.0").supportsKajiAgentRuntime)
        #expect(KajiAgentBunVersion("2.0.0").supportsKajiAgentRuntime)
    }

    @Test
    func parsesVersionPrefixesAndWhitespace() {
        #expect(KajiAgentBunVersion(" v1.3.14\n").supportsKajiAgentRuntime)
        #expect(KajiAgentBunVersion("1.3.14-canary.1").supportsKajiAgentRuntime)
    }
}
