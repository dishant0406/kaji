import Testing

@testable import Droid

struct DroidCodeGraphInstallerTests {
    @Test
    func bundledAdapterIsAvailableInProcessedResources() {
        #expect(DroidCodeGraphInstaller.bundledAdapterURL?.lastPathComponent == "droidcodegraph_runner.py")
    }
}
