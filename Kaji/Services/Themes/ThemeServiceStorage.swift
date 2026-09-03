import Foundation

extension ThemeService {
    nonisolated static func discoverThemes() -> [ThemePreview] {
        var themesByIdentifier: [String: ThemePreview] = [:]
        for directory in themeDirectories() {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { continue }
            for file in files {
                if directory.source == .bundled, !bundledThemeNames.contains(file) {
                    continue
                }
                let url = URL(fileURLWithPath: directory.path).appendingPathComponent(file)
                guard let theme = ThemeFileCodec.parseThemeFile(at: url, source: directory.source, identifierOverride: file) else {
                    continue
                }
                themesByIdentifier[theme.identifier] = theme
            }
        }
        return themesByIdentifier.values.sorted(by: sortThemes)
    }

    nonisolated static func discoverTheme(identifier: String) -> ThemePreview? {
        discoverThemes().first { $0.identifier == identifier }
    }

    @MainActor
    static func updatedConfigContent(
        from content: String,
        themeIdentifier: String,
        theme: ThemePreview?,
        typographyLines: [String]? = nil,
        terminalLines: [String]? = nil
    ) -> String {
        var lines = content.components(separatedBy: .newlines)
        lines.removeAll { line in
            line.trimmingCharacters(in: .whitespaces) == "[colors]"
                || managedThemeKeys.contains { key in isConfigLine(line, for: key) }
                || TermyTypographyDefaults.managedKeys.contains { key in isConfigLine(line, for: key) }
                || TermyTerminalConfigDefaults.managedKeys.contains { key in isConfigLine(line, for: key) }
        }

        let themeLines: [String] = if let theme {
            theme.content.components(separatedBy: .newlines).filter { !$0.hasPrefix("# kaji-") }
        } else {
            ["theme = \"\(themeIdentifier)\""]
        }

        let preserved = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let resolvedTypographyLines = typographyLines
            ?? TermyTypographyDefaults.lines(settings: TerminalSettingsStore.shared.snapshot())
        let resolvedTerminalLines = terminalLines
            ?? TermyTerminalConfigDefaults.lines(settings: TerminalSettingsStore.shared.snapshot())
        return (themeLines + resolvedTypographyLines + resolvedTerminalLines + preserved).joined(separator: "\n")
    }

    nonisolated static func userThemesDirectoryURL() throws -> URL {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("termy", isDirectory: true)
            .appendingPathComponent("themes", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }

    nonisolated private static func sortThemes(_ lhs: ThemePreview, _ rhs: ThemePreview) -> Bool {
        let pinned0 = pinnedThemeNames.contains(lhs.identifier)
        let pinned1 = pinnedThemeNames.contains(rhs.identifier)
        if pinned0 != pinned1 {
            return pinned0
        }
        if pinned0, pinned1 {
            return lhs.name < rhs.name
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    nonisolated private static func themeDirectories() -> [(path: String, source: ThemePreview.Source)] {
        var dirs: [(path: String, source: ThemePreview.Source)] = []
        if let resourcesDir = getenv("TERMY_RESOURCES_DIR").map({ String(cString: $0) }) {
            dirs.append((resourcesDir + "/themes", .external))
        }
        for path in [
            NSHomeDirectory() + "/.config/termy/themes",
        ] where !dirs.contains(where: { $0.path == path }) {
            dirs.append((path, .external))
        }
        if let bundledThemes = Bundle.appResources.resourceURL?.path {
            dirs.append((bundledThemes, .bundled))
        }
        return dirs
    }

    nonisolated private static func isConfigLine(_ line: String, for key: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(key) else { return false }
        let suffix = trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        return suffix.hasPrefix("=")
    }
}
