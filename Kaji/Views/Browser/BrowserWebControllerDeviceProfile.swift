import Foundation

extension BrowserWebController {
    func applyDeviceProfile(_ profile: BrowserDeviceProfile) {
        guard BrowserDeviceProfileApplicationPolicy.shouldApply(current: appliedDeviceProfile, next: profile) else { return }
        deviceProfile = profile
        surface?.applyDeviceProfile(profile)
        browserView?.customUserAgent = profile.userAgent.isEmpty ? nil : profile.userAgent
        appliedDeviceProfile = profile
    }
}
