import AppKit
import SwiftUI

enum KajiTheme {
    @MainActor static var bg: Color { snapshot.bg }
    @MainActor static var nsBg: NSColor { snapshot.nsBg }
    @MainActor static var secondaryBackground: Color { snapshot.secondaryBackground }
    @MainActor static var tertiaryBackground: Color { snapshot.tertiaryBackground }
    @MainActor static var elevatedBackground: Color { snapshot.elevatedBackground }
    @MainActor static var chrome: Color { snapshot.chrome }
    @MainActor static var fg: Color { snapshot.fg }
    @MainActor static var fgMuted: Color { snapshot.fgMuted }
    @MainActor static var fgDim: Color { snapshot.fgDim }
    @MainActor static var selection: Color { snapshot.selection }
    @MainActor static var surface: Color { snapshot.surface }
    @MainActor static var surfaceMuted: Color { snapshot.surfaceMuted }
    @MainActor static var border: Color { snapshot.border }
    @MainActor static var borderStrong: Color { snapshot.borderStrong }
    @MainActor static var hover: Color { snapshot.hover }

    @MainActor static var accent: Color { snapshot.accent }
    @MainActor static var accentSoft: Color { snapshot.accentSoft }

    @MainActor static var diffAddFg: Color { snapshot.diffAddFg }
    @MainActor static var diffRemoveFg: Color { snapshot.diffRemoveFg }
    @MainActor static var diffHunkFg: Color { snapshot.diffHunkFg }
    @MainActor static var diffAddBg: Color { snapshot.diffAddBg }
    @MainActor static var diffRemoveBg: Color { snapshot.diffRemoveBg }
    @MainActor static var diffHunkBg: Color { snapshot.diffHunkBg }

    @MainActor static var nsDiffAdd: NSColor { snapshot.nsDiffAdd }
    @MainActor static var nsDiffRemove: NSColor { snapshot.nsDiffRemove }
    @MainActor static var nsDiffHunk: NSColor { snapshot.nsDiffHunk }
    @MainActor static var nsDiffString: NSColor { snapshot.nsDiffString }
    @MainActor static var nsDiffNumber: NSColor { snapshot.nsDiffNumber }
    @MainActor static var nsDiffComment: NSColor { snapshot.nsDiffComment }

    @MainActor static var colorScheme: ColorScheme { snapshot.colorScheme }

    @MainActor private static var cachedVersion: Int = -1
    @MainActor private static var cachedSnapshot: Snapshot?

    @MainActor private static var snapshot: Snapshot {
        let version = GhosttyService.shared.configVersion
        if let cached = cachedSnapshot, cachedVersion == version {
            return cached
        }
        let newSnapshot = Snapshot(from: GhosttyService.shared)
        cachedSnapshot = newSnapshot
        cachedVersion = version
        return newSnapshot
    }
}

extension KajiTheme {
    struct Snapshot {
        let nsBg: NSColor
        let bg: Color
        let secondaryBackground: Color
        let tertiaryBackground: Color
        let elevatedBackground: Color
        let chrome: Color
        let fg: Color
        let fgMuted: Color
        let fgDim: Color
        let selection: Color
        let surface: Color
        let surfaceMuted: Color
        let border: Color
        let borderStrong: Color
        let hover: Color
        let accent: Color
        let accentSoft: Color
        let diffAddFg: Color
        let diffRemoveFg: Color
        let diffHunkFg: Color
        let diffAddBg: Color
        let diffRemoveBg: Color
        let diffHunkBg: Color
        let nsDiffAdd: NSColor
        let nsDiffRemove: NSColor
        let nsDiffHunk: NSColor
        let nsDiffString: NSColor
        let nsDiffNumber: NSColor
        let nsDiffComment: NSColor
        let colorScheme: ColorScheme

        @MainActor
        init(from service: GhosttyService) {
            let bgColor = service.backgroundColor
            let fgColor = service.foregroundColor
            let selectionColor = service.selectionBackgroundColor
            let accentColor = service.accentColor
            let commentColor = service.paletteColor(at: 8)
                ?? NSColor(srgbRed: 0.361, green: 0.404, blue: 0.451, alpha: 1)
            let srgb = bgColor.usingColorSpace(.sRGB)
            let luminance: CGFloat = if let srgb {
                0.2126 * srgb.redComponent + 0.7152 * srgb.greenComponent + 0.0722 * srgb.blueComponent
            } else {
                0
            }
            let isLight = luminance > 0.5
            let secondaryColor = Self.mix(bgColor, selectionColor, amount: 0.2)
            let tertiaryColor = Self.mix(bgColor, selectionColor, amount: 0.34)
            let elevatedColor = Self.mix(bgColor, selectionColor, amount: 0.46)
            let chromeColor = Self.mix(bgColor, commentColor, amount: 0.08)
            let surfaceColor = Self.mix(bgColor, selectionColor, amount: 0.58)
            let surfaceMutedColor = Self.mix(bgColor, commentColor, amount: 0.16)
            let borderColor = Self.mix(bgColor, commentColor, amount: 0.42)
            let borderStrongColor = Self.mix(bgColor, commentColor, amount: 0.62)
            let hoverColor = Self.mix(surfaceColor, fgColor, amount: 0.05)

            nsBg = bgColor
            bg = Color(nsColor: bgColor)
            secondaryBackground = Color(nsColor: secondaryColor)
            tertiaryBackground = Color(nsColor: tertiaryColor)
            elevatedBackground = Color(nsColor: elevatedColor)
            chrome = Color(nsColor: chromeColor)
            fg = Color(nsColor: fgColor)
            fgMuted = Color(nsColor: fgColor.withAlphaComponent(isLight ? 0.88 : 0.72))
            fgDim = Color(nsColor: fgColor.withAlphaComponent(isLight ? 0.7 : 0.46))
            selection = Color(nsColor: selectionColor)
            surface = Color(nsColor: surfaceColor)
            surfaceMuted = Color(nsColor: surfaceMutedColor)
            border = Color(nsColor: borderColor)
            borderStrong = Color(nsColor: borderStrongColor)
            hover = Color(nsColor: hoverColor)
            accent = Color(nsColor: accentColor)
            accentSoft = Color(nsColor: Self.mix(bgColor, accentColor, amount: 0.16))

            let addColor = service.paletteColor(at: 2) ?? NSColor.systemGreen
            let removeColor = service.paletteColor(at: 1) ?? NSColor.systemRed
            let hunkColor = service.paletteColor(at: 6) ?? accentColor

            nsDiffAdd = addColor
            nsDiffRemove = removeColor
            nsDiffHunk = hunkColor
            nsDiffString = service.paletteColor(at: 2) ?? NSColor.systemGreen
            nsDiffNumber = service.paletteColor(at: 3) ?? NSColor.systemYellow
            nsDiffComment = service.paletteColor(at: 8) ?? fgColor.withAlphaComponent(0.5)

            diffAddFg = Color(nsColor: addColor)
            diffRemoveFg = Color(nsColor: removeColor)
            diffHunkFg = Color(nsColor: hunkColor)
            diffAddBg = Color(nsColor: addColor.withAlphaComponent(0.16))
            diffRemoveBg = Color(nsColor: removeColor.withAlphaComponent(0.16))
            diffHunkBg = Color(nsColor: hunkColor.withAlphaComponent(0.1))

            colorScheme = luminance > 0.5 ? .light : .dark
        }

        private static func mix(_ base: NSColor, _ overlay: NSColor, amount: CGFloat) -> NSColor {
            let clamped = max(0, min(1, amount))
            let baseRGB = base.usingColorSpace(.sRGB) ?? base
            let overlayRGB = overlay.usingColorSpace(.sRGB) ?? overlay
            return NSColor(
                srgbRed: baseRGB.redComponent + (overlayRGB.redComponent - baseRGB.redComponent) * clamped,
                green: baseRGB.greenComponent + (overlayRGB.greenComponent - baseRGB.greenComponent) * clamped,
                blue: baseRGB.blueComponent + (overlayRGB.blueComponent - baseRGB.blueComponent) * clamped,
                alpha: 1
            )
        }
    }
}
