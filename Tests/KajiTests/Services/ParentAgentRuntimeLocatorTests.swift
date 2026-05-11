import Testing
@testable import Kaji

struct ParentAgentRuntimeLocatorTests {
    @Test
    func bundledRuntimeIsPresentInTestBundle() {
        #expect(ParentAgentRuntimeLocator.bundledScriptURL() != nil)
    }
}
