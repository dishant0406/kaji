import Foundation

extension BrowserWebController {
    func goBack() {
        browserView?.goBack()
    }

    func goForward() {
        browserView?.goForward()
    }

    func reload() {
        browserView?.reloadPage()
    }

    func click(selector: String) async throws {
        browserView?.clickSelector(selector)
    }

    func typeText(_ text: String, selector: String) async throws {
        browserView?.typeText(text, selector: selector)
    }

    func readPage() async throws -> String {
        guard let browserView else { return "" }
        return await withCheckedContinuation { continuation in
            browserView.readPage { text in
                continuation.resume(returning: text)
            }
        }
    }

    func screenshotPNG() -> Data? {
        guard let browserView else { return nil }
        return BrowserScreenshotRenderer.pngData(from: browserView)
    }
}
