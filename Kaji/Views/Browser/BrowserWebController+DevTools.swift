import CEFBridge
import Foundation

extension BrowserWebController {
    func showDevTools() {
        browserView?.showDevTools()
    }

    func applyDeviceProfile(_ profile: BrowserDeviceProfile) {
        guard let browserView else { return }
        browserView.applyDeviceProfile(
            withWidth: Int32(profile.width),
            height: Int32(profile.height),
            deviceScaleFactor: profile.deviceScaleFactor,
            userAgent: profile.userAgent,
            mobile: profile.isMobile,
            touch: profile.hasTouch,
            platform: profile.family.rawValue
        )
    }
}
