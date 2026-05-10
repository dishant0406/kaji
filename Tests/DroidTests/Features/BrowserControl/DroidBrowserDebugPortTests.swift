import Testing

@testable import Droid

struct DroidBrowserDebugPortTests {
    @Test
    func allocateReturnsUsableDynamicPort() {
        let port = DroidBrowserDebugPort.allocate()
        #expect(port > 0)
    }
}
