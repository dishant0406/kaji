import AppKit
import Foundation

@MainActor
enum MonacoThemeMapper {
    static func theme() -> [String: MonacoJSONValue] {
        let background = TermyService.shared.backgroundColor
        let foreground = TermyService.shared.foregroundColor
        let isDark = background.kajiPerceivedBrightness < 0.5
        return [
            "name": .string("kaji-editor-theme"),
            "base": .string(isDark ? "vs-dark" : "vs"),
            "colors": .object([
                "editor.background": .string(background.kajiHexRGB),
                "editor.foreground": .string(foreground.kajiHexRGB),
                "editorCursor.foreground": .string(foreground.kajiHexRGB),
                "editor.selectionBackground": .string(foreground.withAlphaComponent(0.18).kajiHexRGBA),
                "editor.inactiveSelectionBackground": .string(foreground.withAlphaComponent(0.10).kajiHexRGBA),
                "editorLineNumber.foreground": .string(foreground.withAlphaComponent(0.38).kajiHexRGBA),
                "editorLineNumber.activeForeground": .string(foreground.withAlphaComponent(0.78).kajiHexRGBA),
                "editorGutter.background": .string(background.kajiHexRGB),
                "editor.lineHighlightBackground": .string(foreground.withAlphaComponent(0.06).kajiHexRGBA),
                "scrollbarSlider.background": .string(foreground.withAlphaComponent(0.18).kajiHexRGBA),
                "scrollbarSlider.hoverBackground": .string(foreground.withAlphaComponent(0.24).kajiHexRGBA),
                "scrollbarSlider.activeBackground": .string(foreground.withAlphaComponent(0.30).kajiHexRGBA),
            ]),
        ]
    }
}

private extension NSColor {
    var kajiHexRGB: String {
        let color = usingColorSpace(.sRGB) ?? self
        return String(
            format: "#%02X%02X%02X",
            Int(color.redComponent * 255),
            Int(color.greenComponent * 255),
            Int(color.blueComponent * 255)
        )
    }

    var kajiHexRGBA: String {
        let color = usingColorSpace(.sRGB) ?? self
        return String(
            format: "#%02X%02X%02X%02X",
            Int(color.redComponent * 255),
            Int(color.greenComponent * 255),
            Int(color.blueComponent * 255),
            Int(color.alphaComponent * 255)
        )
    }

    var kajiPerceivedBrightness: CGFloat {
        let color = usingColorSpace(.sRGB) ?? self
        return 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent
    }
}
