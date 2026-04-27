import AppKit
import Observation
import os
import SwiftUI

private let typographyLogger = Logger(subsystem: "app.droid", category: "AppTypographySettings")

@MainActor
@Observable
final class AppTypographySettings {
    static let shared = AppTypographySettings()

    nonisolated static let defaultFontSize: CGFloat = 15
    nonisolated static let defaultFontFamily = "SF Mono"

    var fontSize: CGFloat = 15 { didSet { saveAndPropagate() } }

    var fontFamily: String = "SF Mono" { didSet { saveAndPropagate() } }

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var isBatchLoading = false

    var scaleFactor: CGFloat {
        Self.clamped(fontSize) / Self.defaultFontSize
    }

    private init() {
        fileURL = DroidFileStorage.fileURL(filename: "app-typography.json")
        load()
    }

    static var availableMonospacedFonts: [String] {
        NSFontManager.shared
            .availableFontFamilies
            .filter { family in
                guard let font = NSFont(name: family, size: 13) else { return false }
                return font.isFixedPitch || family.localizedCaseInsensitiveContains("mono")
                    || family.localizedCaseInsensitiveContains("courier")
                    || family.localizedCaseInsensitiveContains("menlo")
                    || family.localizedCaseInsensitiveContains("consolas")
            }
            .sorted()
    }

    func scaled(_ size: CGFloat) -> CGFloat {
        max(8, size * scaleFactor)
    }

    func uiFont(size: CGFloat, design: Font.Design = .default) -> Font {
        let resolvedSize = scaled(size)
        let resolvedFamily = Self.normalizedFamily(fontFamily)
        if let _ = NSFont(name: resolvedFamily, size: resolvedSize) {
            return .custom(resolvedFamily, size: resolvedSize)
        }
        return .system(size: resolvedSize, weight: .regular, design: design)
    }

    func nsFont(size: CGFloat? = nil) -> NSFont {
        let resolvedSize = size.map(scaled) ?? Self.clamped(fontSize)
        let resolvedFamily = Self.normalizedFamily(fontFamily)
        if let font = NSFont(name: resolvedFamily, size: resolvedSize) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: resolvedSize, weight: .regular)
    }

    func resetToDefaults() {
        isBatchLoading = true
        fontSize = Self.defaultFontSize
        fontFamily = Self.defaultFontFamily
        isBatchLoading = false
        saveAndPropagate()
    }

    private func saveAndPropagate() {
        guard !isBatchLoading else { return }
        save()
        ThemeService.shared.applyDefaultThemeIfNeeded()
    }

    private func load() {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            loadLegacySnapshotIfAvailable()
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            isBatchLoading = true
            fontSize = Self.clamped(snapshot.fontSize)
            fontFamily = snapshot.fontFamily.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? snapshot.fontFamily
                : Self.defaultFontFamily
            isBatchLoading = false
        } catch {
            typographyLogger.error("Failed to load app typography settings: \(error.localizedDescription)")
        }
    }

    private func loadLegacySnapshotIfAvailable() {
        let legacyURL = DroidFileStorage.fileURL(filename: "editor-settings.json")
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return }
        do {
            let data = try Data(contentsOf: legacyURL)
            let snapshot = try JSONDecoder().decode(LegacySnapshot.self, from: data)
            isBatchLoading = true
            fontSize = snapshot.fontSize.map(Self.clamped) ?? Self.defaultFontSize
            fontFamily = snapshot.fontFamily?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? snapshot.fontFamily!
                : Self.defaultFontFamily
            isBatchLoading = false
            save()
        } catch {
            typographyLogger.error("Failed to load legacy typography settings: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let snapshot = Snapshot(
                fontSize: Self.clamped(fontSize),
                fontFamily: Self.normalizedFamily(fontFamily)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            typographyLogger.error("Failed to save app typography settings: \(error.localizedDescription)")
        }
    }

    private static func clamped(_ size: CGFloat) -> CGFloat {
        min(max(size, 10), 36)
    }

    private static func normalizedFamily(_ family: String) -> String {
        let trimmed = family.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultFontFamily : trimmed
    }
}

private struct Snapshot: Codable {
    let fontSize: CGFloat
    let fontFamily: String
}

private struct LegacySnapshot: Codable {
    let fontSize: CGFloat?
    let fontFamily: String?
}
