import Foundation
import WebKit

@MainActor
protocol MonacoMessageTarget: AnyObject {
    func receiveMonacoMessage(_ message: WKScriptMessage)
}

final class MonacoMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: MonacoMessageTarget?

    init(target: MonacoMessageTarget) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        DispatchQueue.main.async { [weak target] in
            target?.receiveMonacoMessage(message)
        }
    }
}
