import Foundation
import WebKit

@MainActor
protocol MarkdownPreviewMessageTarget: AnyObject {
    func receiveMarkdownPreviewMessage(_ message: WKScriptMessage)
}

final class MarkdownPreviewMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: MarkdownPreviewMessageTarget?

    init(target: MarkdownPreviewMessageTarget) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        DispatchQueue.main.async { [weak target] in
            target?.receiveMarkdownPreviewMessage(message)
        }
    }
}
