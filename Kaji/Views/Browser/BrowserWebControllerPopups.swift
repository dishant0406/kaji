import Foundation
import WebKit

extension BrowserWebController {
    func openPopup(url: String) {
        guard let page else { return }
        popupRequested?(page.id, url)
    }

    func openPopup(configuration: WKWebViewConfiguration, features: WKWindowFeatures) -> WKWebView? {
        let popup = KajiBrowserPopupWindow(configuration: configuration, features: features)
        popup.onClose = { [weak self] popup in
            self?.popups.removeAll { $0 === popup }
        }
        popups.append(popup)
        return popup.webView
    }

    func closePopup(webView: WKWebView) {
        guard let index = popups.firstIndex(where: { $0.webView === webView }) else { return }
        let popup = popups.remove(at: index)
        popup.close()
    }

    func recoverTerminated(_ terminatedWebView: WKWebView) {
        guard terminatedWebView === browserView else { return }
        let restoreURL = terminatedWebView.url?.absoluteString ?? page?.url ?? startURL
        teardown(webView: browserView)
        let replacement = KajiBrowserWebViewFactory.make()
        browserView = replacement
        bind(replacement)
        installIfNeeded(replacement, active: activeState ?? true)
        applyDeviceProfile(deviceProfile)
        guard let url = BrowserURLParser.url(from: restoreURL) else { return }
        replacement.load(URLRequest(url: url))
    }
}
