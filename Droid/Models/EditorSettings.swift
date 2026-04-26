import Foundation
import Observation
import os

private let logger = Logger(subsystem: "app.droid", category: "EditorSettings")

@MainActor
@Observable
final class EditorSettings {
    static let shared = EditorSettings()

    enum DefaultEditor: String, Codable, CaseIterable, Identifiable {
        case builtIn
        case terminalCommand

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .builtIn:
                "Built-in Editor"
            case .terminalCommand:
                "Terminal Command"
            }
        }
    }

    var defaultEditor: DefaultEditor = .builtIn { didSet { save() } }
    var externalEditorCommand: String = "vim" { didSet { save() } }

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var isBatchLoading = false

    private init() {
        fileURL = DroidFileStorage.fileURL(filename: "editor-settings.json")
        load()
    }

    func resetToDefaults() {
        isBatchLoading = true
        defaultEditor = .builtIn
        externalEditorCommand = "vim"
        isBatchLoading = false
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            isBatchLoading = true
            defaultEditor = snapshot.defaultEditor ?? snapshot.quickOpenEditor ?? .builtIn
            externalEditorCommand = snapshot.externalEditorCommand ?? "vim"
            isBatchLoading = false
        } catch {
            logger.error("Failed to load editor settings: \(error.localizedDescription)")
        }
    }

    private func save() {
        guard !isBatchLoading else { return }
        do {
            let snapshot = Snapshot(
                defaultEditor: defaultEditor,
                quickOpenEditor: nil,
                externalEditorCommand: externalEditorCommand
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            logger.error("Failed to save editor settings: \(error.localizedDescription)")
        }
    }
}

private struct Snapshot: Codable {
    let defaultEditor: EditorSettings.DefaultEditor?
    let quickOpenEditor: EditorSettings.DefaultEditor?
    let externalEditorCommand: String?
}
