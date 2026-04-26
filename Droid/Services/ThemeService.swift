import AppKit
import Foundation

struct ThemePreview: Identifiable {
    enum Source {
        case bundled
        case external
    }

    let name: String
    let background: NSColor
    let foreground: NSColor
    let palette: [NSColor]
    let source: Source
    let content: String
    var id: String { name }
}

@MainActor @Observable
final class ThemeService {
    static let shared = ThemeService()
    nonisolated static let defaultThemeName = "Droid"
    nonisolated static let pinnedThemeNames: Set<String> = ["Droid"]
    nonisolated static let bundledThemeNames: Set<String> = ["Droid"]
    @ObservationIgnored nonisolated private static let selectedThemeNameKey = "droid.selectedThemeName"
    @ObservationIgnored nonisolated private static let managedThemeKeys = [
        "theme",
        "background",
        "foreground",
        "cursor-color",
        "cursor-text",
        "selection-background",
        "selection-foreground",
        "palette",
    ]

    @ObservationIgnored private let config: DroidConfig

    init(config: DroidConfig = .shared) {
        self.config = config
    }

    func loadThemes() async -> [ThemePreview] {
        await Task.detached { Self.discoverThemes() }.value
    }

    func currentThemeName() -> String? {
        if let selected = UserDefaults.standard.string(forKey: Self.selectedThemeNameKey), !selected.isEmpty {
            return selected
        }
        return config.configValue(for: "theme")?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    func applyDefaultThemeIfNeeded() {
        if let current = currentThemeName(),
           let theme = Self.discoverTheme(named: current),
           theme.source == .bundled
        {
            let existing = config.readGhosttyConfig().trimmingCharacters(in: .whitespacesAndNewlines)
            let expected = Self.updatedConfigContent(from: existing, themeName: current, theme: theme)
            if existing != expected {
                applyTheme(current)
            }
            return
        }

        if let current = currentThemeName(), Self.discoverTheme(named: current) == nil {
            applyTheme(Self.defaultThemeName)
            return
        }

        guard currentThemeName() == nil else { return }
        applyTheme(Self.defaultThemeName)
    }

    func applyTheme(_ name: String) {
        let sanitized = name.filter { $0 != "\"" && $0 != "\n" && $0 != "\r" }
        let theme = Self.discoverTheme(named: sanitized)
        let configContent = Self.updatedConfigContent(
            from: config.readGhosttyConfig(),
            themeName: sanitized,
            theme: theme
        )
        try? config.writeGhosttyConfig(configContent)
        UserDefaults.standard.set(sanitized, forKey: Self.selectedThemeNameKey)
        GhosttyService.shared.reloadConfig()
        NotificationCenter.default.post(name: .themeDidChange, object: nil)
    }

    nonisolated private static func discoverThemes() -> [ThemePreview] {
        var themesByName: [String: ThemePreview] = [:]

        for directory in themeDirectories() {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { continue }
            for file in files {
                if directory.source == .bundled, !bundledThemeNames.contains(file) {
                    continue
                }
                guard let theme = parseThemeFile(
                    atPath: directory.path + "/" + file,
                    name: file,
                    source: directory.source
                ) else { continue }
                themesByName[theme.name] = theme
            }
        }

        return themesByName.values.sorted {
            let pinned0 = pinnedThemeNames.contains($0.name)
            let pinned1 = pinnedThemeNames.contains($1.name)
            if pinned0 != pinned1 { return pinned0 }
            if pinned0, pinned1 { return $0.name < $1.name }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    nonisolated private static func discoverTheme(named name: String) -> ThemePreview? {
        discoverThemes().first { $0.name == name }
    }

    nonisolated private static func themeDirectories() -> [(path: String, source: ThemePreview.Source)] {
        var dirs: [(path: String, source: ThemePreview.Source)] = []
        if let resourcesDir = getenv("GHOSTTY_RESOURCES_DIR").map({ String(cString: $0) }) {
            dirs.append((resourcesDir + "/themes", .external))
        }

        let appBundlePaths = [
            "/Applications/Ghostty.app/Contents/Resources/ghostty/themes",
            NSHomeDirectory() + "/Applications/Ghostty.app/Contents/Resources/ghostty/themes",
        ]
        for path in appBundlePaths where !dirs.contains(where: { $0.path == path }) {
            dirs.append((path, .external))
        }

        let userThemesPath = NSHomeDirectory() + "/.config/ghostty/themes"
        if !dirs.contains(where: { $0.path == userThemesPath }) {
            dirs.append((userThemesPath, .external))
        }

        if let bundledThemes = Bundle.appResources.resourceURL?.path {
            dirs.append((bundledThemes, .bundled))
        }

        return dirs
    }

    nonisolated private static func parseThemeFile(
        atPath path: String,
        name: String,
        source: ThemePreview.Source
    ) -> ThemePreview? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var bg: NSColor?
        var fg: NSColor?
        var palette: [Int: NSColor] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("background"), !trimmed.hasPrefix("background-") {
                bg = extractColor(from: trimmed)
            } else if trimmed.hasPrefix("foreground"), !trimmed.hasPrefix("foreground-") {
                fg = extractColor(from: trimmed)
            } else if trimmed.hasPrefix("palette") {
                parsePaletteEntry(trimmed, into: &palette)
            }
        }
        guard let bg, let fg else { return nil }
        let sortedPalette = (0 ..< 16).compactMap { palette[$0] }
        return ThemePreview(
            name: name,
            background: bg,
            foreground: fg,
            palette: sortedPalette,
            source: source,
            content: content.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    nonisolated private static func updatedConfigContent(
        from content: String,
        themeName: String,
        theme: ThemePreview?
    ) -> String {
        var lines = content.components(separatedBy: .newlines)
        lines.removeAll { line in
            Self.managedThemeKeys.contains { key in
                isConfigLine(line, for: key)
            }
        }

        let themeLines: [String]
        if let theme, theme.source == .bundled {
            themeLines = theme.content.components(separatedBy: .newlines)
        } else {
            themeLines = ["theme = \"\(themeName)\""]
        }

        let preserved = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let typographyLines = GhosttyTypographyDefaults.linesIfMissing(in: preserved)
        return (themeLines + typographyLines + preserved).joined(separator: "\n")
    }

    nonisolated private static func isConfigLine(_ line: String, for key: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(key) else { return false }
        let suffix = trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        return suffix.hasPrefix("=")
    }

    nonisolated private static func parsePaletteEntry(_ line: String, into palette: inout [Int: NSColor]) {
        guard let eqIndex = line.firstIndex(of: "=") else { return }
        let value = line[line.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
        guard let eqIndex2 = value.firstIndex(of: "=") else { return }
        guard let index = Int(value[..<eqIndex2]) else { return }
        guard index >= 0, index < 16 else { return }
        guard let color = parseHex(String(value[value.index(after: eqIndex2)...])) else { return }
        palette[index] = color
    }

    nonisolated private static func extractColor(from line: String) -> NSColor? {
        guard let eqIndex = line.firstIndex(of: "=") else { return nil }
        let value = line[line.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
        return parseHex(value)
    }

    nonisolated private static func parseHex(_ hex: String) -> NSColor? {
        var h = hex
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6, let val = UInt32(h, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((val >> 16) & 0xFF) / 255,
            green: CGFloat((val >> 8) & 0xFF) / 255,
            blue: CGFloat(val & 0xFF) / 255,
            alpha: 1
        )
    }
}
