import Foundation

extension ShortcutActionDispatcher {
    func performRegisteredCommand(_ action: ShortcutAction) -> Bool {
        guard let notification = editorCommandNotification(for: action) else { return false }
        notificationCenter.post(name: notification, object: nil)
        return true
    }

    func editorCommandNotification(for action: ShortcutAction) -> Notification.Name? {
        switch action {
        case .saveFile: .saveActiveEditor
        case .goToSymbol: .goToSymbol
        case .goToLine: .goToLine
        case .inlineEdit: .inlineEdit
        default: nil
        }
    }
}
