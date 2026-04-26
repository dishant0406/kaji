import Foundation
import os

private let cliLauncherLogger = Logger(subsystem: "app.droid", category: "CLILauncherSettings")

struct CLILauncherDefinition: Identifiable, Equatable {
    let id: String
    let displayName: String
    let iconName: String
    let defaultCommand: String
}

struct CLILauncherConfiguration: Identifiable, Equatable {
    let id: String
    let definition: CLILauncherDefinition
    var isEnabled: Bool
    var command: String
}

@MainActor
@Observable
final class CLILauncherSettings {
    static let shared = CLILauncherSettings()

    static let catalog: [CLILauncherDefinition] = [
        .init(id: "codex", displayName: "Codex", iconName: "codex", defaultCommand: "codex"),
        .init(id: "claude", displayName: "Claude Code", iconName: "claude", defaultCommand: "claude"),
        .init(id: "opencode", displayName: "OpenCode", iconName: "opencode", defaultCommand: "opencode"),
    ]

    private(set) var launchers: [CLILauncherConfiguration] = []

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var isBatchLoading = false

    init(fileURL: URL = DroidFileStorage.fileURL(filename: "cli-launchers.json")) {
        self.fileURL = fileURL
        load()
    }

    var enabledLaunchers: [CLILauncherConfiguration] {
        launchers.filter(\.isEnabled)
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        guard let index = launchers.firstIndex(where: { $0.id == id }) else { return }
        launchers[index].isEnabled = enabled
        save()
    }

    func setCommand(_ command: String, for id: String) {
        guard let index = launchers.firstIndex(where: { $0.id == id }) else { return }
        launchers[index].command = command
        save()
    }

    func command(for id: String) -> String {
        launchers.first(where: { $0.id == id })?.command ?? ""
    }

    func isEnabled(id: String) -> Bool {
        launchers.first(where: { $0.id == id })?.isEnabled ?? false
    }

    private func load() {
        launchers = Self.catalog.map {
            .init(id: $0.id, definition: $0, isEnabled: false, command: $0.defaultCommand)
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            let savedByID = Dictionary(uniqueKeysWithValues: snapshot.launchers.map { ($0.id, $0) })
            isBatchLoading = true
            for index in launchers.indices {
                guard let saved = savedByID[launchers[index].id] else { continue }
                launchers[index].isEnabled = saved.isEnabled
                launchers[index].command = saved.command.isEmpty
                    ? launchers[index].definition.defaultCommand
                    : saved.command
            }
            isBatchLoading = false
        } catch {
            cliLauncherLogger.error("Failed to load CLI launcher settings: \(error.localizedDescription)")
        }
    }

    private func save() {
        guard !isBatchLoading else { return }
        do {
            let snapshot = Snapshot(
                launchers: launchers.map {
                    .init(id: $0.id, isEnabled: $0.isEnabled, command: $0.command)
                }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            cliLauncherLogger.error("Failed to save CLI launcher settings: \(error.localizedDescription)")
        }
    }
}

private struct Snapshot: Codable {
    let launchers: [LauncherSnapshot]
}

private struct LauncherSnapshot: Codable {
    let id: String
    let isEnabled: Bool
    let command: String
}
