import AppKit
import SwiftUI

@MainActor
struct KajiEditCommands: Commands {
    let context: KajiCommandContext

    var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                .keyboardShortcut("x", modifiers: .command)

            Button("Copy") {
                if context.isMainWindowFocused, context.terminalPasteboardCommands.copy() {
                    return
                }
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("c", modifiers: .command)

            Button("Paste") {
                if context.isMainWindowFocused, context.terminalPasteboardCommands.paste() {
                    return
                }
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("v", modifiers: .command)

            Button("Select All") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                .keyboardShortcut("a", modifiers: .command)

            Divider()

            Button("Find") {
                guard context.isMainWindowFocused else { return }
                context.performShortcutAction(.findInTerminal)
            }
            .shortcut(for: .findInTerminal, store: context.keyBindings)

            Button("Toggle Footer Terminal") {
                guard context.isMainWindowFocused else { return }
                context.performShortcutAction(.toggleFooterTerminal)
            }
            .shortcut(for: .toggleFooterTerminal, store: context.keyBindings)
        }
    }
}
