import AppKit
import Foundation

@MainActor
enum KajiURLCommandHandler {
    @discardableResult
    static func handle(
        url: URL,
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) -> Bool {
        guard let command = KajiURLCommandParser.parse(url) else { return false }
        do {
            switch command {
            case let .openProject(path):
                _ = try ProjectSelectionService.selectOrAddProject(
                    path: path,
                    appState: appState,
                    projectStore: projectStore,
                    worktreeStore: worktreeStore
                )
            }
            bringAppForward()
            return true
        } catch {
            DebugFileLog.log("CLI", "Failed to handle URL \(url.absoluteString): \(error.localizedDescription)")
            bringAppForward()
            return false
        }
    }

    private static func bringAppForward() {
        for window in NSApp.windows where window.isVisible {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
