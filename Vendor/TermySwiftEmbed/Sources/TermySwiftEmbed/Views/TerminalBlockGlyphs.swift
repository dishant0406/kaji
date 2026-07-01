import CoreGraphics
import Foundation

/// A cell-relative rect (fractions in 0...1) that a block-element glyph fills,
/// plus the fill alpha (shade characters fill the whole cell at partial alpha).
struct TerminalBlockRect: Equatable {
    var left: Double
    var top: Double
    var right: Double
    var bottom: Double
    var alpha: Double
}

/// Cell-filling geometry for Unicode block elements (U+2580–U+259F).
///
/// Font glyphs for these characters only cover the font's ascent/descent box,
/// not the full terminal cell (which is taller whenever line height > 1), so
/// drawing them through CoreText leaves horizontal seams between rows and
/// anti-aliased edges inside pixel art. Drawing them as pixel-snapped rects
/// makes adjacent cells tile seamlessly, matching the GPUI renderer
/// (`crates/terminal_ui/src/grid.rs::block_element_geometry`).
enum TerminalBlockGlyphs {
    /// Converts a cell-relative rect into an absolute rect with every edge
    /// snapped to integer device pixels.
    ///
    /// The fraction is folded into the cell coordinate *before* multiplying so
    /// that shared edges are bit-identical floating-point expressions: row N's
    /// bottom edge is `(N + 1.0) * cellHeight` and row N+1's top edge is
    /// `(N+1 + 0.0) * cellHeight` — the same value, so both round to the same
    /// device pixel and adjacent cells tile without seams at any scale or cell
    /// size. (Snapping the two edges from independently computed cell origins
    /// does NOT guarantee this; rounding can differ by a pixel for fractional
    /// cell heights at 1x scale.)
    static func snappedRect(
        _ rect: TerminalBlockRect,
        col: Int,
        row: Int,
        cellWidth: CGFloat,
        cellHeight: CGFloat,
        paddingX: CGFloat,
        paddingY: CGFloat,
        scale: CGFloat
    ) -> CGRect? {
        let scale = max(1, scale)
        func snap(_ value: CGFloat) -> CGFloat {
            (value * scale).rounded() / scale
        }

        let left = snap(paddingX + (CGFloat(col) + rect.left) * cellWidth)
        let right = snap(paddingX + (CGFloat(col) + rect.right) * cellWidth)
        let top = snap(paddingY + (CGFloat(row) + rect.top) * cellHeight)
        let bottom = snap(paddingY + (CGFloat(row) + rect.bottom) * cellHeight)
        guard right > left, bottom > top else {
            return nil
        }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    static func geometry(for character: Character) -> [TerminalBlockRect]? {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1,
              (0x2580 ... 0x259F).contains(scalar.value)
        else {
            return nil
        }

        switch scalar.value {
        case 0x2580: return [rect(0, 0, 1, 0.5)] // ▀ upper half
        case 0x2581 ... 0x2587: // ▁–▇ lower eighths
            let eighths = Double(scalar.value - 0x2580)
            return [rect(0, 1 - eighths / 8, 1, 1)]
        case 0x2588: return [rect(0, 0, 1, 1)] // █ full block
        case 0x2589 ... 0x258F: // ▉–▏ left eighths
            let eighths = Double(0x2590 - scalar.value)
            return [rect(0, 0, eighths / 8, 1)]
        case 0x2590: return [rect(0.5, 0, 1, 1)] // ▐ right half
        case 0x2591: return [rect(0, 0, 1, 1, alpha: 0.25)] // ░ light shade
        case 0x2592: return [rect(0, 0, 1, 1, alpha: 0.50)] // ▒ medium shade
        case 0x2593: return [rect(0, 0, 1, 1, alpha: 0.75)] // ▓ dark shade
        case 0x2594: return [rect(0, 0, 1, 1.0 / 8.0)] // ▔ upper eighth
        case 0x2595: return [rect(7.0 / 8.0, 0, 1, 1)] // ▕ right eighth
        case 0x2596: return quadrants(lowerLeft: true)
        case 0x2597: return quadrants(lowerRight: true)
        case 0x2598: return quadrants(upperLeft: true)
        case 0x2599: return quadrants(upperLeft: true, lowerLeft: true, lowerRight: true)
        case 0x259A: return quadrants(upperLeft: true, lowerRight: true)
        case 0x259B: return quadrants(upperLeft: true, upperRight: true, lowerLeft: true)
        case 0x259C: return quadrants(upperLeft: true, upperRight: true, lowerRight: true)
        case 0x259D: return quadrants(upperRight: true)
        case 0x259E: return quadrants(upperRight: true, lowerLeft: true)
        case 0x259F: return quadrants(upperRight: true, lowerLeft: true, lowerRight: true)
        default: return nil
        }
    }

    private static func rect(
        _ left: Double,
        _ top: Double,
        _ right: Double,
        _ bottom: Double,
        alpha: Double = 1.0
    ) -> TerminalBlockRect {
        TerminalBlockRect(left: left, top: top, right: right, bottom: bottom, alpha: alpha)
    }

    private static func quadrants(
        upperLeft: Bool = false,
        upperRight: Bool = false,
        lowerLeft: Bool = false,
        lowerRight: Bool = false
    ) -> [TerminalBlockRect] {
        var rects: [TerminalBlockRect] = []
        if upperLeft {
            rects.append(rect(0, 0, 0.5, 0.5))
        }
        if upperRight {
            rects.append(rect(0.5, 0, 1, 0.5))
        }
        if lowerLeft {
            rects.append(rect(0, 0.5, 0.5, 1))
        }
        if lowerRight {
            rects.append(rect(0.5, 0.5, 1, 1))
        }
        return rects
    }
}
