import Testing

@testable import Kaji

struct KajiCodeGraphInstallerTests {
    @Test
    func bundledAdapterIsAvailableInProcessedResources() {
        #expect(KajiCodeGraphInstaller.bundledAdapterURL?.lastPathComponent == "kajicodegraph_runner.py")
    }
}
