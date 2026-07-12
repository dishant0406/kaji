import SwiftUI

extension View {
    @ViewBuilder
    func shortcut(for action: ShortcutAction, store: KeyBindingStore) -> some View {
        if let combo = store.assignedCombo(for: action) {
            keyboardShortcut(combo.swiftUIKeyEquivalent, modifiers: combo.swiftUIModifiers)
        } else {
            self
        }
    }
}
