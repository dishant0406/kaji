import Foundation

@MainActor
enum FooterLauncherShortcutResolver {
    static func displayName(for action: ShortcutAction, settings: CLILauncherSettings = .shared) -> String? {
        if action == .openKajiAgentSplit {
            return "Open KajiCode"
        }
        guard let index = action.footerLauncherIndex else { return nil }
        let launchers = settings.footerLaunchers
        guard launchers.indices.contains(index) else { return nil }
        return "Open \(launchers[index].definition.displayName)"
    }
}
