import SwiftUI

@MainActor
struct KajiSidebarNavigationCommands: Commands {
    let context: KajiCommandContext

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            navigationButton("Toggle Sidebar", action: .toggleSidebar)

            Divider()

            navigationButton("Switch Worktree...", action: .switchWorktree)

            Divider()

            navigationButton("Next Project", action: .nextProject)
            navigationButton("Previous Project", action: .previousProject)

            Divider()

            ForEach(1 ... 9, id: \.self) { index in
                if let action = ShortcutAction.projectAction(for: index) {
                    navigationButton("Project \(index)", action: action)
                }
            }

            Divider()

            navigationButton("Theme Picker", action: .toggleThemePicker)
            navigationButton("AI Usage", action: .toggleAIUsage)
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
