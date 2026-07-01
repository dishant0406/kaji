import CoreGraphics
import Foundation

/// Stroke weight for one arm of a box-drawing connector. Light strokes are 1x
/// the base width, heavy strokes are 2x, and double strokes are two parallel
/// light lines separated by one light-width gap.
enum TerminalBoxLineStyle: Equatable {
    case none
    case light
    case heavy
    case double

    var isHeavy: Bool { self == .heavy }
    var isDouble: Bool { self == .double }
}

/// Four-arm style descriptor for a rectangular box-drawing character. Rounded
/// corners (U+256D–U+2570) and diagonals (U+2571–U+2573) are not representable
/// here; they are stroked as paths instead (see `strokeKind(for:)`).
struct TerminalBoxSegments: Equatable {
    var up: TerminalBoxLineStyle
    var down: TerminalBoxLineStyle
    var left: TerminalBoxLineStyle
    var right: TerminalBoxLineStyle
}

/// Box-drawing glyphs that cannot be expressed as axis-aligned rects and are
/// stroked as paths at draw time instead.
enum TerminalBoxStrokeKind: Equatable {
    case roundedCorner
    case diagonal
}

struct TerminalRoundedCornerPathSpec: Equatable {
    var start: CGPoint
    var curveStart: CGPoint
    var controlA: CGPoint
    var controlB: CGPoint
    var curveEnd: CGPoint
    var end: CGPoint
}

/// Cell-filling geometry for Unicode box-drawing characters (U+2500–U+257F),
/// mirroring `crates/terminal_ui/src/grid.rs::box_draw_segments` and
/// `box_draw_geometry` edge
/// placement). Like block elements, font glyphs for these don't span the full
/// line-height-padded cell, so connectors drawn through the font leave seams.
enum TerminalBoxDrawing {
    /// Returns the rects composing a rectangular box-drawing connector, in
    /// cell-relative fractions, or nil for rounded corners, diagonals, and
    /// non-box-drawing characters.
    static func rectGeometry(
        for character: Character,
        cellWidth: CGFloat,
        cellHeight: CGFloat,
        fontSize: CGFloat
    ) -> [TerminalBlockRect]? {
        guard let segments = segments(for: character) else {
            return nil
        }
        return geometry(
            segments: segments,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            fontSize: fontSize
        )
    }

    /// Rounded corners and diagonals are stroked as paths instead of rects.
    static func strokeKind(for character: Character) -> TerminalBoxStrokeKind? {
        guard let scalar = singleScalar(of: character) else {
            return nil
        }
        switch scalar {
        case 0x256D ... 0x2570: return .roundedCorner
        case 0x2571 ... 0x2573: return .diagonal
        default: return nil
        }
    }

    static func strokeWidth(fontSize: CGFloat) -> CGFloat {
        max(1, (fontSize * 0.0675).rounded(.up))
    }

    static func roundedCornerPathSpec(
        for glyph: Character,
        in cell: CGRect,
        strokeWidth: CGFloat
    ) -> TerminalRoundedCornerPathSpec? {
        guard cell.width > 0, cell.height > 0 else {
            return nil
        }

        let radius = max(min(cell.width, cell.height) - strokeWidth, 0) / 2
        let controlDistance = radius * 0.5522847498307936
        let centerX = snappedStrokeCenter(origin: cell.minX, size: cell.width, strokeWidth: strokeWidth)
        let centerY = snappedStrokeCenter(origin: cell.minY, size: cell.height, strokeWidth: strokeWidth)
        let leftCenter = CGPoint(x: cell.minX, y: centerY)
        let rightCenter = CGPoint(x: cell.maxX, y: centerY)
        let topCenter = CGPoint(x: centerX, y: cell.minY)
        let bottomCenter = CGPoint(x: centerX, y: cell.maxY)

        switch glyph {
        case "\u{256D}": // ╭
            let curveStart = CGPoint(x: centerX, y: centerY + radius)
            let curveEnd = CGPoint(x: centerX + radius, y: centerY)
            return TerminalRoundedCornerPathSpec(
                start: bottomCenter,
                curveStart: curveStart,
                controlA: CGPoint(x: curveStart.x, y: curveStart.y - controlDistance),
                controlB: CGPoint(x: curveEnd.x - controlDistance, y: curveEnd.y),
                curveEnd: curveEnd,
                end: rightCenter
            )
        case "\u{256E}": // ╮
            let curveStart = CGPoint(x: centerX, y: centerY + radius)
            let curveEnd = CGPoint(x: centerX - radius, y: centerY)
            return TerminalRoundedCornerPathSpec(
                start: bottomCenter,
                curveStart: curveStart,
                controlA: CGPoint(x: curveStart.x, y: curveStart.y - controlDistance),
                controlB: CGPoint(x: curveEnd.x + controlDistance, y: curveEnd.y),
                curveEnd: curveEnd,
                end: leftCenter
            )
        case "\u{256F}": // ╯
            let curveStart = CGPoint(x: centerX, y: centerY - radius)
            let curveEnd = CGPoint(x: centerX - radius, y: centerY)
            return TerminalRoundedCornerPathSpec(
                start: topCenter,
                curveStart: curveStart,
                controlA: CGPoint(x: curveStart.x, y: curveStart.y + controlDistance),
                controlB: CGPoint(x: curveEnd.x + controlDistance, y: curveEnd.y),
                curveEnd: curveEnd,
                end: leftCenter
            )
        case "\u{2570}": // ╰
            let curveStart = CGPoint(x: centerX, y: centerY - radius)
            let curveEnd = CGPoint(x: centerX + radius, y: centerY)
            return TerminalRoundedCornerPathSpec(
                start: topCenter,
                curveStart: curveStart,
                controlA: CGPoint(x: curveStart.x, y: curveStart.y + controlDistance),
                controlB: CGPoint(x: curveEnd.x - controlDistance, y: curveEnd.y),
                curveEnd: curveEnd,
                end: rightCenter
            )
        default:
            return nil
        }
    }

    private static func singleScalar(of character: Character) -> UInt32? {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1
        else {
            return nil
        }
        return scalar.value
    }

    /// Midpoint of a stroke pixel-snapped to integer boundaries: rounds both
    /// stroke edges independently, then averages.
    private static func snappedStrokeCenter(origin: CGFloat, size: CGFloat, strokeWidth: CGFloat) -> CGFloat {
        let center = origin + size / 2
        let minEdge = (center - strokeWidth / 2).rounded()
        let maxEdge = (center + strokeWidth / 2).rounded()
        return (minEdge + maxEdge) / 2
    }

    // MARK: - Segment table (parity with grid.rs::box_draw_segments)

    static func segments(for character: Character) -> TerminalBoxSegments? {
        guard let scalar = singleScalar(of: character),
              (0x2500 ... 0x257F).contains(scalar)
        else {
            return nil
        }

        // Dashed variants map to their solid counterparts, matching the GPUI
        // renderer.
        switch scalar {
        case 0x2500,
             0x2504,
             0x2508,
             0x254C: return arms(.none, .none, .light, .light)
        case 0x2501,
             0x2505,
             0x2509,
             0x254D: return arms(.none, .none, .heavy, .heavy)
        case 0x2502,
             0x2506,
             0x250A,
             0x254E: return arms(.light, .light, .none, .none)
        case 0x2503,
             0x2507,
             0x250B,
             0x254F: return arms(.heavy, .heavy, .none, .none)
        case 0x250C: return arms(.none, .light, .none, .light)
        case 0x250D: return arms(.none, .light, .none, .heavy)
        case 0x250E: return arms(.none, .heavy, .none, .light)
        case 0x250F: return arms(.none, .heavy, .none, .heavy)
        case 0x2510: return arms(.none, .light, .light, .none)
        case 0x2511: return arms(.none, .light, .heavy, .none)
        case 0x2512: return arms(.none, .heavy, .light, .none)
        case 0x2513: return arms(.none, .heavy, .heavy, .none)
        case 0x2514: return arms(.light, .none, .none, .light)
        case 0x2515: return arms(.light, .none, .none, .heavy)
        case 0x2516: return arms(.heavy, .none, .none, .light)
        case 0x2517: return arms(.heavy, .none, .none, .heavy)
        case 0x2518: return arms(.light, .none, .light, .none)
        case 0x2519: return arms(.light, .none, .heavy, .none)
        case 0x251A: return arms(.heavy, .none, .light, .none)
        case 0x251B: return arms(.heavy, .none, .heavy, .none)
        case 0x251C: return arms(.light, .light, .none, .light)
        case 0x251D: return arms(.light, .light, .none, .heavy)
        case 0x251E: return arms(.heavy, .light, .none, .light)
        case 0x251F: return arms(.light, .heavy, .none, .light)
        case 0x2520: return arms(.heavy, .heavy, .none, .light)
        case 0x2521: return arms(.light, .heavy, .none, .heavy)
        case 0x2522: return arms(.heavy, .light, .none, .heavy)
        case 0x2523: return arms(.heavy, .heavy, .none, .heavy)
        case 0x2524: return arms(.light, .light, .light, .none)
        case 0x2525: return arms(.light, .light, .heavy, .none)
        case 0x2526: return arms(.heavy, .light, .light, .none)
        case 0x2527: return arms(.light, .heavy, .light, .none)
        case 0x2528: return arms(.heavy, .heavy, .light, .none)
        case 0x2529: return arms(.light, .heavy, .heavy, .none)
        case 0x252A: return arms(.heavy, .light, .heavy, .none)
        case 0x252B: return arms(.heavy, .heavy, .heavy, .none)
        case 0x252C: return arms(.none, .light, .light, .light)
        case 0x252D: return arms(.none, .light, .heavy, .light)
        case 0x252E: return arms(.none, .light, .light, .heavy)
        case 0x252F: return arms(.none, .light, .heavy, .heavy)
        case 0x2530: return arms(.none, .heavy, .light, .light)
        case 0x2531: return arms(.none, .heavy, .heavy, .light)
        case 0x2532: return arms(.none, .heavy, .light, .heavy)
        case 0x2533: return arms(.none, .heavy, .heavy, .heavy)
        case 0x2534: return arms(.light, .none, .light, .light)
        case 0x2535: return arms(.light, .none, .heavy, .light)
        case 0x2536: return arms(.light, .none, .light, .heavy)
        case 0x2537: return arms(.light, .none, .heavy, .heavy)
        case 0x2538: return arms(.heavy, .none, .light, .light)
        case 0x2539: return arms(.heavy, .none, .heavy, .light)
        case 0x253A: return arms(.heavy, .none, .light, .heavy)
        case 0x253B: return arms(.heavy, .none, .heavy, .heavy)
        case 0x253C: return arms(.light, .light, .light, .light)
        case 0x253D: return arms(.light, .light, .heavy, .light)
        case 0x253E: return arms(.light, .light, .light, .heavy)
        case 0x253F: return arms(.light, .light, .heavy, .heavy)
        case 0x2540: return arms(.heavy, .light, .light, .light)
        case 0x2541: return arms(.light, .heavy, .light, .light)
        case 0x2542: return arms(.heavy, .heavy, .light, .light)
        case 0x2543: return arms(.heavy, .light, .heavy, .light)
        case 0x2544: return arms(.heavy, .light, .light, .heavy)
        case 0x2545: return arms(.light, .heavy, .heavy, .light)
        case 0x2546: return arms(.light, .heavy, .light, .heavy)
        case 0x2547: return arms(.light, .heavy, .heavy, .heavy)
        case 0x2548: return arms(.heavy, .light, .heavy, .heavy)
        case 0x2549: return arms(.heavy, .heavy, .heavy, .light)
        case 0x254A: return arms(.heavy, .heavy, .light, .heavy)
        case 0x254B: return arms(.heavy, .heavy, .heavy, .heavy)
        case 0x2550: return arms(.none, .none, .double, .double)
        case 0x2551: return arms(.double, .double, .none, .none)
        case 0x2552: return arms(.none, .light, .none, .double)
        case 0x2553: return arms(.none, .double, .none, .light)
        case 0x2554: return arms(.none, .double, .none, .double)
        case 0x2555: return arms(.none, .light, .double, .none)
        case 0x2556: return arms(.none, .double, .light, .none)
        case 0x2557: return arms(.none, .double, .double, .none)
        case 0x2558: return arms(.light, .none, .none, .double)
        case 0x2559: return arms(.double, .none, .none, .light)
        case 0x255A: return arms(.double, .none, .none, .double)
        case 0x255B: return arms(.light, .none, .double, .none)
        case 0x255C: return arms(.double, .none, .light, .none)
        case 0x255D: return arms(.double, .none, .double, .none)
        case 0x255E: return arms(.light, .light, .none, .double)
        case 0x255F: return arms(.double, .double, .none, .light)
        case 0x2560: return arms(.double, .double, .none, .double)
        case 0x2561: return arms(.light, .light, .double, .none)
        case 0x2562: return arms(.double, .double, .light, .none)
        case 0x2563: return arms(.double, .double, .double, .none)
        case 0x2564: return arms(.none, .light, .double, .double)
        case 0x2565: return arms(.none, .double, .light, .light)
        case 0x2566: return arms(.none, .double, .double, .double)
        case 0x2567: return arms(.light, .none, .double, .double)
        case 0x2568: return arms(.double, .none, .light, .light)
        case 0x2569: return arms(.double, .none, .double, .double)
        case 0x256A: return arms(.light, .light, .double, .double)
        case 0x256B: return arms(.double, .double, .light, .light)
        case 0x256C: return arms(.double, .double, .double, .double)
        case 0x256D ... 0x2570: return nil // rounded corners — stroked paths
        case 0x2571 ... 0x2573: return nil // diagonals — stroked paths
        case 0x2574: return arms(.none, .none, .light, .none)
        case 0x2575: return arms(.light, .none, .none, .none)
        case 0x2576: return arms(.none, .none, .none, .light)
        case 0x2577: return arms(.none, .light, .none, .none)
        case 0x2578: return arms(.none, .none, .heavy, .none)
        case 0x2579: return arms(.heavy, .none, .none, .none)
        case 0x257A: return arms(.none, .none, .none, .heavy)
        case 0x257B: return arms(.none, .heavy, .none, .none)
        case 0x257C: return arms(.none, .none, .light, .heavy)
        case 0x257D: return arms(.light, .heavy, .none, .none)
        case 0x257E: return arms(.none, .none, .heavy, .light)
        case 0x257F: return arms(.heavy, .light, .none, .none)
        default: return nil
        }
    }

    private static func arms(
        _ up: TerminalBoxLineStyle,
        _ down: TerminalBoxLineStyle,
        _ left: TerminalBoxLineStyle,
        _ right: TerminalBoxLineStyle
    ) -> TerminalBoxSegments {
        TerminalBoxSegments(up: up, down: down, left: left, right: right)
    }

    // MARK: - Geometry (parity with grid.rs::box_draw_geometry)

    /// Converts a segment descriptor into cell-relative rects using the
    /// `linesChar` edge placement: each arm is built independently, then
    /// overlapping collinear runs are merged so simple glyphs stay compact.
    static func geometry(
        segments: TerminalBoxSegments,
        cellWidth: CGFloat,
        cellHeight: CGFloat,
        fontSize: CGFloat
    ) -> [TerminalBlockRect] {
        let lightPx = strokeWidth(fontSize: fontSize)
        let heavyPx = lightPx * 2

        let hLightTop = max(cellHeight - lightPx, 0) / 2
        let hLightBottom = min(hLightTop + lightPx, cellHeight)
        let hHeavyTop = max(cellHeight - heavyPx, 0) / 2
        let hHeavyBottom = min(hHeavyTop + heavyPx, cellHeight)
        let hDoubleTop = max(hLightTop - lightPx, 0)
        let hDoubleBottom = min(hLightBottom + lightPx, cellHeight)

        let vLightLeft = max(cellWidth - lightPx, 0) / 2
        let vLightRight = min(vLightLeft + lightPx, cellWidth)
        let vHeavyLeft = max(cellWidth - heavyPx, 0) / 2
        let vHeavyRight = min(vHeavyLeft + heavyPx, cellWidth)
        let vDoubleLeft = max(vLightLeft - lightPx, 0)
        let vDoubleRight = min(vLightRight + lightPx, cellWidth)

        let upBottom: CGFloat = if segments.left.isHeavy || segments.right.isHeavy {
            hHeavyBottom
        } else if segments.left != segments.right || segments.down == segments.up {
            (segments.left.isDouble || segments.right.isDouble)
                ? hDoubleBottom : hLightBottom
        } else if segments.left == .none && segments.right == .none {
            hLightBottom
        } else {
            hLightTop
        }

        let downTop: CGFloat = if segments.left.isHeavy || segments.right.isHeavy {
            hHeavyTop
        } else if segments.left != segments.right || segments.up == segments.down {
            (segments.left.isDouble || segments.right.isDouble)
                ? hDoubleTop : hLightTop
        } else if segments.left == .none && segments.right == .none {
            hLightTop
        } else {
            hLightBottom
        }

        let leftRight: CGFloat = if segments.up.isHeavy || segments.down.isHeavy {
            vHeavyRight
        } else if segments.up != segments.down || segments.left == segments.right {
            (segments.up.isDouble || segments.down.isDouble)
                ? vDoubleRight : vLightRight
        } else if segments.up == .none && segments.down == .none {
            vLightRight
        } else {
            vLightLeft
        }

        let rightLeft: CGFloat = if segments.up.isHeavy || segments.down.isHeavy {
            vHeavyLeft
        } else if segments.up != segments.down || segments.right == segments.left {
            (segments.up.isDouble || segments.down.isDouble)
                ? vDoubleLeft : vLightLeft
        } else if segments.up == .none, segments.down == .none {
            vLightLeft
        } else {
            vLightRight
        }

        var rects: [TerminalBlockRect] = []

        func push(_ leftPx: CGFloat, _ topPx: CGFloat, _ rightPx: CGFloat, _ bottomPx: CGFloat) {
            let left = min(max(leftPx, 0), cellWidth)
            let right = min(max(rightPx, 0), cellWidth)
            let top = min(max(topPx, 0), cellHeight)
            let bottom = min(max(bottomPx, 0), cellHeight)
            guard right > left, bottom > top else {
                return
            }
            rects.append(TerminalBlockRect(
                left: left / cellWidth,
                top: top / cellHeight,
                right: right / cellWidth,
                bottom: bottom / cellHeight,
                alpha: 1.0
            ))
        }

        switch segments.up {
        case .none:
            break
        case .light:
            push(vLightLeft, 0, vLightRight, upBottom)
        case .heavy:
            push(vHeavyLeft, 0, vHeavyRight, upBottom)
        case .double:
            let leftBottom = segments.left == .double ? hLightTop : upBottom
            let rightBottom = segments.right == .double ? hLightTop : upBottom
            push(vDoubleLeft, 0, vLightLeft, leftBottom)
            push(vLightRight, 0, vDoubleRight, rightBottom)
        }

        switch segments.right {
        case .none:
            break
        case .light:
            push(rightLeft, hLightTop, cellWidth, hLightBottom)
        case .heavy:
            push(rightLeft, hHeavyTop, cellWidth, hHeavyBottom)
        case .double:
            let topLeft = segments.up == .double ? vLightRight : rightLeft
            let bottomLeft = segments.down == .double ? vLightRight : rightLeft
            push(topLeft, hDoubleTop, cellWidth, hLightTop)
            push(bottomLeft, hLightBottom, cellWidth, hDoubleBottom)
        }

        switch segments.down {
        case .none:
            break
        case .light:
            push(vLightLeft, downTop, vLightRight, cellHeight)
        case .heavy:
            push(vHeavyLeft, downTop, vHeavyRight, cellHeight)
        case .double:
            let leftTop = segments.left == .double ? hLightBottom : downTop
            let rightTop = segments.right == .double ? hLightBottom : downTop
            push(vDoubleLeft, leftTop, vLightLeft, cellHeight)
            push(vLightRight, rightTop, vDoubleRight, cellHeight)
        }

        switch segments.left {
        case .none:
            break
        case .light:
            push(0, hLightTop, leftRight, hLightBottom)
        case .heavy:
            push(0, hHeavyTop, leftRight, hHeavyBottom)
        case .double:
            let topRight = segments.up == .double ? vLightLeft : leftRight
            let bottomRight = segments.down == .double ? vLightLeft : leftRight
            push(0, hDoubleTop, topRight, hLightTop)
            push(0, hLightBottom, bottomRight, hDoubleBottom)
        }

        return mergeCollinearOverlaps(rects)
    }

    /// Merges any pair of rects that share the same axis track and overlap or
    /// touch, so a simple light cross stays two rects instead of fragmenting.
    private static func mergeCollinearOverlaps(_ input: [TerminalBlockRect]) -> [TerminalBlockRect] {
        let epsilon = 1e-6
        var rects = input

        var i = 0
        while i < rects.count {
            var j = i + 1
            while j < rects.count {
                let a = rects[i]
                let b = rects[j]

                let sameVerticalTrack = abs(a.left - b.left) <= epsilon
                    && abs(a.right - b.right) <= epsilon
                    && a.top <= b.bottom + epsilon
                    && b.top <= a.bottom + epsilon
                let sameHorizontalTrack = abs(a.top - b.top) <= epsilon
                    && abs(a.bottom - b.bottom) <= epsilon
                    && a.left <= b.right + epsilon
                    && b.left <= a.right + epsilon

                if sameVerticalTrack || sameHorizontalTrack {
                    rects[i] = TerminalBlockRect(
                        left: min(a.left, b.left),
                        top: min(a.top, b.top),
                        right: max(a.right, b.right),
                        bottom: max(a.bottom, b.bottom),
                        alpha: max(a.alpha, b.alpha)
                    )
                    rects.remove(at: j)
                } else {
                    j += 1
                }
            }
            i += 1
        }
        return rects
    }
}
