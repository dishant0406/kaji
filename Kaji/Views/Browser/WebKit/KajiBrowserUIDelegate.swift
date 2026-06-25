import AppKit
import WebKit

@MainActor
final class KajiBrowserUIDelegate: NSObject, WKUIDelegate {
    var openPopup: ((WKWebViewConfiguration, WKWindowFeatures) -> WKWebView?)?
    var closeRequested: ((WKWebView) -> Void)?
    var dialogRequested: ((KajiBrowserPendingDialog, WKWebView) -> Void)?

    func webViewDidClose(_ webView: WKWebView) {
        closeRequested?(webView)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url, shouldOpenExternally(url) {
            NSWorkspace.shared.open(url)
            return nil
        }
        return openPopup?(configuration, windowFeatures)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let dialog = KajiBrowserPendingDialog(type: "alert", message: message) { _, _ in completionHandler() }
        dialogRequested?(dialog, webView)
        presentFallback(dialog, webView: webView)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let dialog = KajiBrowserPendingDialog(type: "confirm", message: message) { accept, _ in completionHandler(accept) }
        dialogRequested?(dialog, webView)
        presentFallback(dialog, webView: webView)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let dialog = KajiBrowserPendingDialog(type: "prompt", message: prompt, defaultText: defaultText ?? "") { accept, text in
            completionHandler(accept ? text ?? defaultText ?? "" : nil)
        }
        dialogRequested?(dialog, webView)
        presentFallback(dialog, webView: webView)
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !parameters.allowsDirectories
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        if let window = webView.window {
            panel.beginSheetModal(for: window) { result in
                completionHandler(result == .OK ? panel.urls : nil)
            }
            return
        }
        completionHandler(panel.runModal() == .OK ? panel.urls : nil)
    }

    private func present(_ alert: NSAlert, webView: WKWebView, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = webView.window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    private func presentFallback(_ dialog: KajiBrowserPendingDialog, webView: WKWebView) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !dialog.resolved else { return }
            presentDialog(dialog, webView: webView)
        }
    }

    private func presentDialog(_ dialog: KajiBrowserPendingDialog, webView: WKWebView) {
        let alert = NSAlert()
        alert.messageText = title(for: webView)
        alert.informativeText = dialog.message
        alert.addButton(withTitle: "OK")
        if dialog.type != "alert" {
            alert.addButton(withTitle: "Cancel")
        }
        if dialog.type == "prompt" {
            let field = NSTextField(string: dialog.defaultText)
            field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
            alert.accessoryView = field
        }
        present(alert, webView: webView) { response in
            let text = (alert.accessoryView as? NSTextField)?.stringValue
            dialog.resolve(accept: response == .alertFirstButtonReturn, promptText: text)
        }
    }

    private func title(for webView: WKWebView) -> String {
        webView.url?.host.map { "The page at \($0) says:" } ?? "This page says:"
    }

    private func shouldOpenExternally(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return !["http", "https", "about", "file", "data", "blob"].contains(scheme)
    }
}
