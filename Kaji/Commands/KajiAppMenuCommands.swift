import AppKit
import SwiftUI

@MainActor
struct KajiAppMenuCommands: Commands {
    let context: KajiCommandContext

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(KajiAppMenuCommand.settings.title) {
                NotificationCenter.default.post(name: .toggleSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(after: .appSettings) {
            Button(KajiAppMenuCommand.openConfiguration.title) {
                NSWorkspace.shared.open(
                    [context.config.termyConfigURL],
                    withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                    configuration: NSWorkspace.OpenConfiguration()
                )
            }

            Button(KajiAppMenuCommand.reloadConfiguration.title) {
                context.performShortcutAction(.reloadConfig)
            }
            .shortcut(for: .reloadConfig, store: context.keyBindings)

            Divider()

            Button(KajiAppMenuCommand.checkForUpdates.title) {
                context.updateService.checkForUpdates()
            }
            .disabled(!context.updateService.canCheckForUpdates)
        }
    }
}
