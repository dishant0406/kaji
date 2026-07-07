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

    @Test("generated app bundle registers kaji URL scheme")
    func generatedBundleRegistersKajiURLScheme() throws {
        let plist = SwiftRunBundleLauncher.infoPlist()
        let urlTypes = try #require(plist["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = try #require(urlTypes.first?["CFBundleURLSchemes"] as? [String])

        #expect(schemes.contains("kaji"))
    }
}
