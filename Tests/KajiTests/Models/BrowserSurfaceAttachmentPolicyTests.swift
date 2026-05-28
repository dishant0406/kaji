import Testing
@testable import Kaji

@Suite("BrowserSurfaceAttachmentPolicy")
struct BrowserSurfaceAttachmentPolicyTests {
    @Test("releases only stale previous surfaces")
    func releasesOnlyStalePreviousSurfaces() {
        #expect(BrowserSurfaceAttachmentPolicy.shouldReleasePreviousSurface(hasPreviousSurface: true, sameSurface: false))
        #expect(!BrowserSurfaceAttachmentPolicy.shouldReleasePreviousSurface(hasPreviousSurface: true, sameSurface: true))
        #expect(!BrowserSurfaceAttachmentPolicy.shouldReleasePreviousSurface(hasPreviousSurface: false, sameSurface: false))
    }

    @Test("uninstalls only owned browser views")
    func uninstallsOnlyOwnedBrowserViews() {
        #expect(BrowserSurfaceAttachmentPolicy.shouldUninstallBrowserView(surfaceOwnsBrowserView: true))
        #expect(!BrowserSurfaceAttachmentPolicy.shouldUninstallBrowserView(surfaceOwnsBrowserView: false))
    }

    @Test("deactivates browser only for current detached surface")
    func deactivatesBrowserOnlyForCurrentDetachedSurface() {
        #expect(BrowserSurfaceAttachmentPolicy.shouldDeactivateBrowserOnDetach(isCurrentSurface: true, hasBrowserView: true))
        #expect(!BrowserSurfaceAttachmentPolicy.shouldDeactivateBrowserOnDetach(isCurrentSurface: false, hasBrowserView: true))
        #expect(!BrowserSurfaceAttachmentPolicy.shouldDeactivateBrowserOnDetach(isCurrentSurface: true, hasBrowserView: false))
    }
}
