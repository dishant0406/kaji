import Foundation

@MainActor
enum FooterLauncherShortcutResolver {
    static func displayName(for action: ShortcutAction, settings: CLILauncherSettings = .shared) -> String? {
        if action == .openKajiAgentSplit {
            return "Open Kaji Agent"
        }
        guard let index = action.footerLauncherIndex else { return nil }
        let launchers = settings.enabledLaunchers
        guard launchers.indices.contains(index) else { return nil }
        return "Open \(launchers[index].definition.displayName)"
    }
}
