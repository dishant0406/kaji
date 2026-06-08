import Testing

@testable import Kaji

@Suite("BrowserDeviceProfileApplicationPolicy")
struct BrowserDeviceProfileApplicationPolicyTests {
    @Test("applies only changed profiles")
    func appliesOnlyChangedProfiles() {
        let desktop = BrowserDeviceProfiles.profile(for: BrowserDeviceProfiles.desktopID)
        let phone = BrowserDeviceProfiles.profile(for: "iphone-15-pro")

        #expect(BrowserDeviceProfileApplicationPolicy.shouldApply(current: nil, next: desktop))
        #expect(!BrowserDeviceProfileApplicationPolicy.shouldApply(current: desktop, next: desktop))
        #expect(BrowserDeviceProfileApplicationPolicy.shouldApply(current: desktop, next: phone))
    }
}
