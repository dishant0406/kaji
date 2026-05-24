import Foundation

struct AppCommand: Identifiable, Equatable {
    let id: ShortcutAction
    let title: String
    let category: String
    let shortcut: KeyCombo?

    init(shortcut: ShortcutDefinition) {
        id = shortcut.action
        title = shortcut.displayName
        category = shortcut.category
        self.shortcut = shortcut.defaultCombo
    }
}
