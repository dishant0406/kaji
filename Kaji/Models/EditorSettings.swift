import Foundation
import Observation
import os

private let logger = Logger(subsystem: "app.kaji", category: "EditorSettings")

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
    var showsLineNumbers = true { didSet { save() } }
    var highlightsActiveLine = true { didSet { save() } }
    var showsIndentGuides = true { didSet { save() } }
    var rendersWhitespace = false { didSet { save() } }
    var highlightsMatchingBrackets = true { didSet { save() } }
    var wordWrapEnabled = false { didSet { save() } }
    var autoClosesPairs = true { didSet { save() } }
    var autoIndentsNewLines = true { didSet { save() } }
    var tabSize: Int = 4 {
        didSet {
            let clamped = Self.clampedTabSize(tabSize)
            if tabSize != clamped {
                tabSize = clamped
                return
            }
            save()
        }
    }

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var isBatchLoading = false

    private init() {
        DebugFileLog.log("EditorSettings", "init started")
        fileURL = KajiFileStorage.fileURL(filename: "editor-settings.json")
        DebugFileLog.log("EditorSettings", "resolved fileURL=\(fileURL.path)")
        load()
        DebugFileLog.log(
            "EditorSettings",
            "init completed defaultEditor=\(defaultEditor.rawValue) command=\(externalEditorCommand) lineNumbers=\(showsLineNumbers) activeLine=\(highlightsActiveLine) indent=\(showsIndentGuides) whitespace=\(rendersWhitespace) brackets=\(highlightsMatchingBrackets) tabSize=\(tabSize)"
        )
    }

    func resetToDefaults() {
        isBatchLoading = true
        defaultEditor = .builtIn
        externalEditorCommand = "vim"
        showsLineNumbers = true
        highlightsActiveLine = true
        showsIndentGuides = true
        rendersWhitespace = false
        highlightsMatchingBrackets = true
        wordWrapEnabled = false
        autoClosesPairs = true
        autoIndentsNewLines = true
        tabSize = 4
        isBatchLoading = false
        save()
    }

    private func load() {
        DebugFileLog.log("EditorSettings", "load started path=\(fileURL.path)")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            DebugFileLog.log("EditorSettings", "load skipped missing file path=\(fileURL.path)")
            return
        }
        do {
            DebugFileLog.log("EditorSettings", "reading data path=\(fileURL.path)")
            let data = try Data(contentsOf: fileURL)
            DebugFileLog.log("EditorSettings", "read bytes=\(data.count) path=\(fileURL.path)")
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            DebugFileLog.log("EditorSettings", "decoded snapshot path=\(fileURL.path)")
            isBatchLoading = true
            defaultEditor = snapshot.defaultEditor ?? snapshot.quickOpenEditor ?? .builtIn
            externalEditorCommand = snapshot.externalEditorCommand ?? "vim"
            showsLineNumbers = snapshot.showsLineNumbers ?? true
            highlightsActiveLine = snapshot.highlightsActiveLine ?? true
            showsIndentGuides = snapshot.showsIndentGuides ?? true
            rendersWhitespace = snapshot.rendersWhitespace ?? false
            highlightsMatchingBrackets = snapshot.highlightsMatchingBrackets ?? true
            wordWrapEnabled = snapshot.wordWrapEnabled ?? false
            autoClosesPairs = snapshot.autoClosesPairs ?? true
            autoIndentsNewLines = snapshot.autoIndentsNewLines ?? true
            tabSize = Self.clampedTabSize(snapshot.tabSize ?? 4)
            isBatchLoading = false
            DebugFileLog.log("EditorSettings", "load applied path=\(fileURL.path)")
        } catch {
            DebugFileLog.logError("EditorSettings", error, context: "load failed path=\(fileURL.path)")
            logger.error("Failed to load editor settings: \(error.localizedDescription)")
        }
    }

    private func save() {
        guard !isBatchLoading else { return }
        do {
            let snapshot = Snapshot(
                defaultEditor: defaultEditor,
                quickOpenEditor: nil,
                externalEditorCommand: externalEditorCommand,
                showsLineNumbers: showsLineNumbers,
                highlightsActiveLine: highlightsActiveLine,
                showsIndentGuides: showsIndentGuides,
                rendersWhitespace: rendersWhitespace,
                highlightsMatchingBrackets: highlightsMatchingBrackets,
                wordWrapEnabled: wordWrapEnabled,
                autoClosesPairs: autoClosesPairs,
                autoIndentsNewLines: autoIndentsNewLines,
                tabSize: tabSize
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

    private static func clampedTabSize(_ value: Int) -> Int {
        min(max(value, 2), 8)
    }
}

private struct Snapshot: Codable {
    let defaultEditor: EditorSettings.DefaultEditor?
    let quickOpenEditor: EditorSettings.DefaultEditor?
    let externalEditorCommand: String?
    let showsLineNumbers: Bool?
    let highlightsActiveLine: Bool?
    let showsIndentGuides: Bool?
    let rendersWhitespace: Bool?
    let highlightsMatchingBrackets: Bool?
    let wordWrapEnabled: Bool?
    let autoClosesPairs: Bool?
    let autoIndentsNewLines: Bool?
    let tabSize: Int?
}
