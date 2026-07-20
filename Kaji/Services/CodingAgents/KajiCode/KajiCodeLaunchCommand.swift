import Foundation

enum KajiCodeLaunchCommand {
    @MainActor
    static func split() -> String {
        let saved = CLILauncherSettings.shared.command(for: "kajicode").trimmingCharacters(in: .whitespacesAndNewlines)
        return saved.isEmpty ? KajiCodeCommandBuilder.splitCommand() : CLILauncherCommandResolver.resolve(saved)
    }
}
