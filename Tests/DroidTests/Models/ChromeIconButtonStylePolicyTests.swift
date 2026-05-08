import Testing

@testable import Droid

struct ChromeIconButtonStylePolicyTests {
    @Test("inactive icon buttons never draw a border")
    func inactiveButtonsAreBorderless() {
        #expect(ChromeIconButtonStylePolicy.borderOpacity(active: false, isTahoe: false) == 0)
        #expect(ChromeIconButtonStylePolicy.borderOpacity(active: false, isTahoe: true) == 0)
    }

    @Test("Tahoe icon buttons keep hover fill without a border")
    func tahoeButtonsRemainBorderlessWhenActive() {
        #expect(ChromeIconButtonStylePolicy.borderOpacity(active: true, isTahoe: true) == 0)
    }

    @Test("legacy icon buttons keep the existing active border")
    func legacyButtonsKeepActiveBorder() {
        #expect(ChromeIconButtonStylePolicy.borderOpacity(active: true, isTahoe: false) == 1)
    }
}
