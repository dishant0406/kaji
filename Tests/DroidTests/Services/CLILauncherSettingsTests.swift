import Foundation
import Testing
@testable import Droid

struct CLILauncherSettingsTests {
    @Test
    @MainActor
    func loadsCatalogDefaultsWhenFileIsMissing() {
        let tempURL = tempFileURL()
        let settings = CLILauncherSettings(fileURL: tempURL)

        #expect(settings.launchers.count == 3)
        #expect(settings.isEnabled(id: "codex") == false)
        #expect(settings.command(for: "codex") == "codex")
        #expect(settings.command(for: "claude") == "claude")
    }

    @Test
    @MainActor
    func savesAndReloadsLauncherOverrides() {
        let tempURL = tempFileURL()

        let first = CLILauncherSettings(fileURL: tempURL)
        first.setEnabled(true, for: "codex")
        first.setCommand("codex --approval-mode full-auto", for: "codex")
        first.setEnabled(true, for: "claude")

        let second = CLILauncherSettings(fileURL: tempURL)
        #expect(second.isEnabled(id: "codex"))
        #expect(second.command(for: "codex") == "codex --approval-mode full-auto")
        #expect(second.isEnabled(id: "claude"))
        #expect(second.command(for: "claude") == "claude")
    }

    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }
}
