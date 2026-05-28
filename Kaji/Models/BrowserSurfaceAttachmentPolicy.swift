import Foundation

enum BrowserSurfaceAttachmentPolicy {
    static func shouldReleasePreviousSurface(hasPreviousSurface: Bool, sameSurface: Bool) -> Bool {
        hasPreviousSurface && !sameSurface
    }

    static func shouldUninstallBrowserView(surfaceOwnsBrowserView: Bool) -> Bool {
        surfaceOwnsBrowserView
    }

    static func shouldDeactivateBrowserOnDetach(isCurrentSurface: Bool, hasBrowserView: Bool) -> Bool {
        isCurrentSurface && hasBrowserView
    }
}
