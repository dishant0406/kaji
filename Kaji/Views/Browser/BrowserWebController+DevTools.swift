import CEFBridge
import Foundation

extension BrowserWebController {
    func evaluateJavaScript(_ script: String) async -> String {
        guard let browserView else { return "Browser is not ready." }
        return await withCheckedContinuation { continuation in
            browserView.evaluateJavaScript(script) { result in
                continuation.resume(returning: result)
            }
        }
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
