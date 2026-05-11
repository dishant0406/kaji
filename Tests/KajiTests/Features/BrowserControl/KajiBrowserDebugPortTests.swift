import Testing

@testable import Kaji

struct KajiBrowserDebugPortTests {
    @Test
    func allocateReturnsUsableDynamicPort() {
        let port = KajiBrowserDebugPort.allocate()
        #expect(port > 0)
    }
}
