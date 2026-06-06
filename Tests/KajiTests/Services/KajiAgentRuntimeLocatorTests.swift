import Foundation
import Testing

@testable import Kaji

struct KajiAgentRuntimeLocatorTests {
    @Test
    func bundledRuntimeIsPresentInTestBundle() {
        #expect(KajiAgentRuntimeLocator.bundledScriptURL() != nil)
    }

    @Test
    func bundledRuntimeResolvesFlattenedProcessedResource() throws {
        let url = try #require(KajiAgentRuntimeLocator.bundledScriptURL())
        #expect(url.lastPathComponent == "kaji-agent-runtime.mjs")
    }
}
