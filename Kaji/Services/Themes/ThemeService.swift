import AppKit
import Foundation

@MainActor @Observable
final class ThemeService {
    static let shared = ThemeService()
    nonisolated static let defaultThemeName = "Kaji"
    nonisolated static let pinnedThemeNames: Set<String> = ["Kaji"]
    nonisolated static let bundledThemeNames: Set<String> = ["Kaji"]
    nonisolated private static let selectedThemeNameKey = "kaji.selectedThemeName"
    nonisolated static let managedThemeKeys = [
        "theme",
        "background",
        "foreground",
        "cursor",
        "cursor-color",
        "cursor-text",
        "selection-background",
        "selection-foreground",
        "palette",
        "black",
        "red",
        "green",
        "yellow",
        "blue",
        "magenta",
        "cyan",
        "white",
        "bright_black",
        "bright_red",
        "bright_green",
        "bright_yellow",
        "bright_blue",
        "bright_magenta",
        "bright_cyan",
        "bright_white",
    ]

    private let config: KajiConfig

    init(config: KajiConfig = .shared) {
        self.config = config
    }

    func loadThemes() async -> [ThemePreview] {
        await Task.detached { Self.discoverThemes() }.value
    }

    func currentThemeName() -> String? {
        currentThemeIdentifier()
    }

    func currentThemeIdentifier() -> String? {
        if let selected = UserDefaults.standard.string(forKey: Self.selectedThemeNameKey), !selected.isEmpty {
            return selected
        }
        return config.configValue(for: "theme")?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    func currentThemeDisplayName() -> String? {
        guard let identifier = currentThemeIdentifier() else { return nil }
        return Self.discoverTheme(identifier: identifier)?.name ?? identifier
    }

    func prepareDraft() -> ThemeDraft {
        let seed = currentThemePreview()?.draft ?? ThemeDraft.kajiDefaults
        return ThemeDraft(name: "", slug: "", colors: seed.colors)
    }

    func suggestedSlug(for value: String) -> String {
        ThemeFileCodec.uniqueSlug(ThemeFileCodec.slugify(value), existing: Set(Self.discoverThemes().map(\.identifier)))
    }

    func applyDefaultThemeIfNeeded() {
        if let current = currentThemeIdentifier(),
           let theme = Self.discoverTheme(identifier: current)
        {
            let existing = config.readTermyConfig().trimmingCharacters(in: .whitespacesAndNewlines)
            let expected = Self.updatedConfigContent(from: existing, themeIdentifier: current, theme: theme)
            if existing != expected {
                applyTheme(current)
            }
            return
        }

        if let current = currentThemeIdentifier(), Self.discoverTheme(identifier: current) == nil {
            applyTheme(Self.defaultThemeName)
            return
        }

        guard currentThemeIdentifier() == nil else { return }
        applyTheme(Self.defaultThemeName)
    }

    func applyTheme(_ identifier: String) {
        let sanitized = identifier.filter { $0 != "\"" && $0 != "\n" && $0 != "\r" }
        let theme = Self.discoverTheme(identifier: sanitized)
        let configContent = Self.updatedConfigContent(
            from: config.readTermyConfig(),
            themeIdentifier: sanitized,
            theme: theme
        )
        try? config.writeTermyConfig(configContent)
        UserDefaults.standard.set(sanitized, forKey: Self.selectedThemeNameKey)
        TermyService.shared.reloadConfig()
        NotificationCenter.default.post(name: .themeDidChange, object: nil)
    }

    func createTheme(_ draft: ThemeDraft) throws -> ThemePreview {
        guard let normalized = ThemeFileCodec.normalizedDraft(draft) else { throw ThemeServiceError.invalidThemeFile }
        let identifiers = Set(Self.discoverThemes().map(\.identifier))
        guard !identifiers.contains(normalized.slug) else { throw ThemeServiceError.duplicateTheme }
        guard let content = ThemeFileCodec.buildContent(from: normalized) else { throw ThemeServiceError.invalidThemeFile }
        let url = try Self.userThemesDirectoryURL().appendingPathComponent(normalized.slug)
        try content.write(to: url, atomically: true, encoding: .utf8)
        guard let preview = ThemeFileCodec.parseThemeFile(at: url, source: .external) else {
            throw ThemeServiceError.invalidThemeFile
        }
        applyTheme(preview.identifier)
        return preview
    }

    func importThemes() throws -> Int {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK else { throw ThemeServiceError.importCancelled }

        var importedCount = 0
        var lastError: Error?
        for url in panel.urls {
            do {
                _ = try importTheme(at: url)
                importedCount += 1
            } catch {
                lastError = error
            }
        }

        if importedCount > 0 {
            return importedCount
        }
        throw lastError ?? ThemeServiceError.invalidThemeFile
    }

    func exportTheme(_ theme: ThemePreview) throws {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = theme.identifier
        guard panel.runModal() == .OK, let url = panel.url else { throw ThemeServiceError.saveCancelled }
        try theme.content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func currentThemePreview() -> ThemePreview? {
        guard let identifier = currentThemeIdentifier() else { return nil }
        return Self.discoverTheme(identifier: identifier)
    }

    private func importTheme(at url: URL) throws -> ThemePreview {
        guard let imported = ThemeFileCodec.parseThemeFile(at: url, source: .external) else {
            throw ThemeServiceError.invalidThemeFile
        }
        let identifiers = Set(Self.discoverThemes().map(\.identifier))
        let slug = ThemeFileCodec.uniqueSlug(imported.draft.slug, existing: identifiers)
        let draft = ThemeDraft(name: imported.name, slug: slug, colors: imported.draft.colors)
        guard let content = ThemeFileCodec.buildContent(from: draft) else { throw ThemeServiceError.invalidThemeFile }
        let destination = try Self.userThemesDirectoryURL().appendingPathComponent(slug)
        try content.write(to: destination, atomically: true, encoding: .utf8)
        guard let preview = ThemeFileCodec.parseThemeFile(at: destination, source: .external) else {
            throw ThemeServiceError.invalidThemeFile
        }
        return preview
    }
}
