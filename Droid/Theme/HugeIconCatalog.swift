import Foundation

enum HugeIconCatalog {
    private static let cssFileName = "hgi-stroke-rounded"

    private static let symbolMap: [String: String] = [
        "arrow.2.squarepath": "file-sync",
        "arrow.clockwise": "reload",
        "arrow.counterclockwise": "arrow-turn-backward",
        "arrow.down": "arrow-down-01",
        "arrow.down.circle.fill": "download-square-01",
        "arrow.down.right.and.arrow.up.left": "square-arrow-shrink-02",
        "arrow.triangle.2.circlepath": "reload",
        "arrow.triangle.branch": "git-branch",
        "arrow.triangle.merge": "git-merge",
        "arrow.triangle.pull": "git-pull-request",
        "arrow.up": "arrow-up-01",
        "arrow.up.and.down": "arrow-up-down",
        "arrow.up.left.and.arrow.down.right": "square-arrow-expand-02",
        "arrow.up.right.square": "link-square-02",
        "arrow.uturn.backward": "arrow-turn-backward",
        "bell": "notification-03",
        "bell.badge": "notification-03",
        "bell.slash": "notification-off-03",
        "chart.bar": "analytics-01",
        "checkmark": "tick-02",
        "checkmark.circle.fill": "checkmark-circle-02",
        "chevron.down": "arrow-down-01",
        "chevron.left": "arrow-left-01",
        "chevron.left.forwardslash.chevron.right": "html-5",
        "chevron.right": "arrow-right-01",
        "chevron.up": "arrow-up-01",
        "chevron.up.chevron.down": "sort-by-down-01",
        "clock": "clock-01",
        "cloud": "cloud",
        "curlybraces": "code",
        "doc": "file-01",
        "doc.richtext": "notebook-01",
        "doc.text": "file-02",
        "exclamationmark.triangle": "alert-02",
        "exclamationmark.triangle.fill": "alert-02",
        "file.diff": "file-sync",
        "folder": "folder-01",
        "folder.fill": "folder-open",
        "gearshape": "settings-01",
        "info.circle": "information-circle",
        "j.square": "java-script",
        "keyboard": "keyboard",
        "line.3.horizontal.decrease.circle": "filter-horizontal",
        "line.3.horizontal.decrease.circle.fill": "filter-horizontal",
        "lock.fill": "lock",
        "macwindow.badge.plus": "dashboard-square-add",
        "memorychip": "chip",
        "magnifyingglass": "search-01",
        "minus": "minus-sign",
        "network": "globe",
        "p.square": "source-code",
        "paintbrush": "paint-brush-01",
        "paintpalette": "paint-board",
        "pencil.circle": "git-pull-request-draft",
        "pencil.line": "edit-02",
        "pin": "pin",
        "pin.fill": "pin",
        "plus": "add-01",
        "plus.square.dashed": "add-square",
        "point.3.connected.trianglepath.dotted": "git-branch",
        "rectangle": "layout-2-row",
        "rectangle.split.2x1": "layout-2-column",
        "square.split.1x2": "layout-2-row",
        "square.split.2x1": "layout-2-column",
        "sidebar.left": "sidebar-left-01",
        "sparkles": "sparkles",
        "square.stack.3d.up": "layers-02",
        "swift": "source-code",
        "t.square": "typescript-01",
        "tag": "tag-01",
        "terminal": "computer-terminal-01",
        "xmark": "cancel-01",
        "xmark.circle": "cancel-circle",
        "xmark.octagon.fill": "alert-circle",
    ]

    private static let glyphMap: [String: String] = loadGlyphMap()

    static func glyph(for systemName: String) -> String? {
        guard let iconName = symbolMap[systemName] else { return nil }
        return glyphMap[iconName]
    }

    private static func loadGlyphMap() -> [String: String] {
        guard let url = Bundle.hugeIconResourceURL(forResource: cssFileName, withExtension: "css") else { return [:] }
        guard let css = try? String(contentsOf: url, encoding: .utf8) else { return [:] }

        var glyphs: [String: String] = [:]
        for iconName in Set(symbolMap.values) {
            guard let glyph = glyphValue(for: iconName, in: css) else { continue }
            glyphs[iconName] = glyph
        }
        return glyphs
    }

    static func glyphValue(for iconName: String, in css: String) -> String? {
        let pattern = #"\.hgi-stroke\.hgi-\#(NSRegularExpression.escapedPattern(for: iconName)):before\{content:"([^"]+)"\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(css.startIndex..., in: css)
        guard let match = regex.firstMatch(in: css, range: range) else { return nil }
        guard let glyphRange = Range(match.range(at: 1), in: css) else { return nil }
        return String(css[glyphRange])
    }
}
