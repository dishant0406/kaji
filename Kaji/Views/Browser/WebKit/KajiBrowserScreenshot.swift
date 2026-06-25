import AppKit
import WebKit

@MainActor
enum KajiBrowserScreenshot {
    static func pngData(from webView: WKWebView, fullPage: Bool, target: String?, selector: String?) async throws -> Data? {
        let image = try await image(from: webView, fullPage: fullPage, target: target, selector: selector)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    static func image(from webView: WKWebView, fullPage: Bool, target: String?, selector: String?) async throws -> NSImage {
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = true
        if let rect = try await rect(in: webView, fullPage: fullPage, target: target, selector: selector) {
            configuration.rect = rect
        }
        return try await withCheckedThrowingContinuation { continuation in
            webView.takeSnapshot(with: configuration) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let image else {
                    continuation.resume(throwing: KajiBrowserScreenshotError.empty)
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }

    private static func rect(in webView: WKWebView, fullPage: Bool, target: String?, selector: String?) async throws -> CGRect? {
        if fullPage {
            let value = try await KajiBrowserJavaScript.evaluate(pageRectScript, in: webView) as? [String: Any]
            return rect(from: value)
        }
        guard target?.isEmpty == false || selector?.isEmpty == false else { return nil }
        let script = elementRectScript(target: target, selector: selector)
        let value = try await KajiBrowserJavaScript.evaluate(script, in: webView) as? [String: Any]
        return rect(from: value)
    }

    private static func rect(from value: [String: Any]?) -> CGRect? {
        guard let value,
              let x = value["x"] as? Double,
              let y = value["y"] as? Double,
              let width = value["width"] as? Double,
              let height = value["height"] as? Double,
              width > 0,
              height > 0
        else { return nil }
        return CGRect(x: x, y: y, width: min(width, 16384), height: min(height, 16384))
    }

    private static let pageRectScript = """
    (() => ({
      x: 0,
      y: 0,
      width: Math.max(document.documentElement.scrollWidth, document.body ? document.body.scrollWidth : 0, innerWidth),
      height: Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0, innerHeight)
    }))()
    """

    private static func elementRectScript(target: String?, selector: String?) -> String {
        let target = KajiBrowserJavaScript.literal(target ?? "")
        let selector = KajiBrowserJavaScript.literal(selector ?? "")
        return """
        (() => {
          const state = window.__kajiBrowserState || {};
          const key = \(target) || \(selector);
          const css = \(selector) || (state.snapshotSelectors && state.snapshotSelectors[key]) || key;
          const el = css ? document.querySelector(css) : null;
          if (!el) return null;
          el.scrollIntoView({ block: 'center', inline: 'center' });
          const rect = el.getBoundingClientRect();
          return { x: rect.left, y: rect.top, width: rect.width, height: rect.height };
        })()
        """
    }
}

enum KajiBrowserScreenshotError: Error {
    case empty
}
