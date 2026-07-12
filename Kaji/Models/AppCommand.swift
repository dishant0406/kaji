import Foundation

struct AppCommand: Identifiable, Equatable {
    let id: ShortcutAction
    let title: String
    let category: String

    init(shortcut: ShortcutDefinition) {
        id = shortcut.action
        title = shortcut.displayName
        category = shortcut.category
    }
}
