import SwiftUI

@MainActor
struct KajiWindowNavigationCommands: Commands {
    let context: KajiCommandContext

    var body: some Commands {
        CommandGroup(after: .windowList) {
            navigationButton("Next Tab", action: .nextTab)
            navigationButton("Previous Tab", action: .previousTab)

            Divider()

            ForEach(1 ... 9, id: \.self) { index in
                if let action = ShortcutAction.tabAction(for: index) {
                    navigationButton("Tab \(index)", action: action)
                }
            }
        }
    }

    private func navigationButton(_ title: String, action: ShortcutAction) -> some View {
        Button(title) {
            guard context.isMainWindowFocused else { return }
            context.performShortcutAction(action)
        }
        .shortcut(for: action, store: context.keyBindings)
    }
}
