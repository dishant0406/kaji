import AppKit
import CEFBridge

enum BrowserScreenshotRenderer {
    @MainActor
    static func pngData(from browserView: KajiCEFBrowserView) -> Data? {
        let bounds = browserView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        guard let bitmap = browserView.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        browserView.cacheDisplay(in: bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }
}
