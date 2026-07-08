import AppKit
import SwiftUI

@MainActor
struct KajiWorkspaceCommands: Commands {
    let context: KajiCommandContext

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Project...") {
                context.performShortcutAction(.openProject)
            }
            .shortcut(for: .openProject, store: context.keyBindings)

            workspaceButton("New Tab", action: .newTab)
            workspaceButton("Source Control", action: .openVCSTab)
            workspaceButton("Quick Open", action: .quickOpen)
            workspaceButton("Ask", action: .ask)
            workspaceButton("Save", action: .saveFile)

            Divider()

            Button("Close Tab") {
                guard context.isMainWindowFocused else {
                    NSApp.keyWindow?.performClose(nil)
                    return
                }
                context.performShortcutAction(.closeTab)
            }
            .shortcut(for: .closeTab, store: context.keyBindings)

            Divider()

            workspaceButton("Rename Tab", action: .renameTab)
            workspaceButton("Pin/Unpin Tab", action: .pinUnpinTab)

            Divider()

            workspaceButton("Split Right", action: .splitRight)
            workspaceButton("Split Down", action: .splitDown)
            workspaceButton("Close Pane", action: .closePane)
            workspaceButton("Focus Pane Left", action: .focusPaneLeft)
            workspaceButton("Focus Pane Right", action: .focusPaneRight)
            workspaceButton("Focus Pane Up", action: .focusPaneUp)
            workspaceButton("Focus Pane Down", action: .focusPaneDown)
        }
    }

    private func workspaceButton(_ title: String, action: ShortcutAction) -> some View {
        Button(title) {
            guard context.isMainWindowFocused else { return }
            context.performShortcutAction(action)
        }
        .shortcut(for: action, store: context.keyBindings)
    }
}
