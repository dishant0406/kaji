import Testing
@testable import Droid

struct ParentAgentRuntimeLocatorTests {
    @Test
    func bundledRuntimeIsPresentInTestBundle() {
        #expect(ParentAgentRuntimeLocator.bundledScriptURL() != nil)
    }
}
