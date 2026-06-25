import AppKit
import WebKit

@MainActor
final class KajiBrowserPopupWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    let webView: WKWebView
    var onClose: ((KajiBrowserPopupWindow) -> Void)?

    init(configuration: WKWebViewConfiguration, features: WKWindowFeatures) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        let rect = Self.rect(features: features)
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Browser"
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        onClose?(self)
    }

    private static func rect(features: WKWindowFeatures) -> NSRect {
        let width = CGFloat(truncating: features.width ?? 900)
        let height = CGFloat(truncating: features.height ?? 700)
        return NSRect(x: 0, y: 0, width: max(360, width), height: max(320, height))
    }
}
