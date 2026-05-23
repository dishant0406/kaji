import AppKit
import Foundation

enum MarkdownPreviewThemeBuilder {
    @MainActor
    static func current() -> MarkdownPreviewTheme {
        MarkdownPreviewTheme(
            bg: hex(KajiTheme.nsBg),
            fg: hex(GhosttyService.shared.foregroundColor),
            muted: hex(GhosttyService.shared.foregroundColor.withAlphaComponent(0.72)),
            dim: hex(GhosttyService.shared.foregroundColor.withAlphaComponent(0.46)),
            surface: hex(mix(KajiTheme.nsBg, GhosttyService.shared.selectionBackgroundColor, amount: 0.2)),
            border: hex(mix(KajiTheme.nsBg, GhosttyService.shared.foregroundColor, amount: 0.18)),
            accent: hex(GhosttyService.shared.accentColor),
            soft: hex(mix(KajiTheme.nsBg, GhosttyService.shared.accentColor, amount: 0.16))
        )
    }

    private static func hex(_ color: NSColor) -> String {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        let red = Int(round(max(0, min(1, srgb.redComponent)) * 255))
        let green = Int(round(max(0, min(1, srgb.greenComponent)) * 255))
        let blue = Int(round(max(0, min(1, srgb.blueComponent)) * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private static func mix(_ base: NSColor, _ overlay: NSColor, amount: CGFloat) -> NSColor {
        guard let a = base.usingColorSpace(.sRGB), let b = overlay.usingColorSpace(.sRGB) else { return base }
        return NSColor(
            srgbRed: a.redComponent * (1 - amount) + b.redComponent * amount,
            green: a.greenComponent * (1 - amount) + b.greenComponent * amount,
            blue: a.blueComponent * (1 - amount) + b.blueComponent * amount,
            alpha: 1
        )
    }
}
