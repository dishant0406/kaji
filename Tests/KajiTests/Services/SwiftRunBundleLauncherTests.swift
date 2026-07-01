import Testing

@testable import Kaji

@Suite("Swift run bundle launcher")
struct SwiftRunBundleLauncherTests {
    @Test("generated app bundle keeps privacy usage descriptions")
    func generatedBundleIncludesPrivacyDescriptions() {
        let plist = SwiftRunBundleLauncher.infoPlist()

        #expect(plist["NSMicrophoneUsageDescription"] as? String != nil)
        #expect(plist["NSSpeechRecognitionUsageDescription"] as? String != nil)
        #expect(plist["NSCameraUsageDescription"] as? String != nil)
        #expect(plist["NSAppleEventsUsageDescription"] as? String != nil)
    }
}
