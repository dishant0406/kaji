import Testing
@testable import Kaji

struct UpdateServiceTests {
    @Test
    func comparesSemanticVersions() {
        #expect(UpdateService.isVersion("0.0.6", newerThan: "0.0.5"))
        #expect(UpdateService.isVersion("v0.1.0", newerThan: "0.0.9"))
        #expect(!UpdateService.isVersion("0.0.5", newerThan: "0.0.5"))
        #expect(!UpdateService.isVersion("0.0.4", newerThan: "0.0.5"))
    }
}
