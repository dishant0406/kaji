import Foundation

extension BrowserWebController {
    func handleDialog(accept: Bool, promptText: String?) -> Bool {
        guard let dialog = pendingDialogs.first(where: { !$0.resolved }) else { return false }
        dialog.resolve(accept: accept, promptText: promptText)
        pendingDialogs.removeAll { $0.resolved }
        return true
    }

    func pendingDialogPayloads() -> [[String: Any]] {
        pendingDialogs.filter { !$0.resolved }.map(\.payload)
    }
}
