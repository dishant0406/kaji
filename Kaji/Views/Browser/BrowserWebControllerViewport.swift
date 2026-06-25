import AppKit

extension BrowserWebController {
    func resizeViewport(width: Int, height: Int) {
        let profile = BrowserDeviceProfile(
            id: "custom-\(width)x\(height)",
            title: "Custom",
            family: .desktop,
            width: width,
            height: height,
            deviceScaleFactor: 1,
            userAgent: "",
            isMobile: false,
            hasTouch: false
        )
        deviceProfile = profile
        surface?.applyDeviceProfile(profile)
        browserView?.setFrameSize(NSSize(width: width, height: height))
    }
}
