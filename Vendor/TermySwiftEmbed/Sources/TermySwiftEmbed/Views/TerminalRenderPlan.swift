import Foundation

/// A horizontal run of identically-styled background cells on one row.
struct TerminalBackgroundRun: Equatable {
    var row: Int
    var startCol: Int
    var cols: Int
    var color: TerminalRGBA
    var opacity: Double

    func canAppend(cell: TerminalCell, opacity: Double) -> Bool {
        cell.row == row
            && cell.col == startCol + cols
            && cell.background == color
            && opacity == self.opacity
    }
}

/// A run of glyphs that share a foreground color and weight on one row.
struct TerminalTextSegment: Equatable {
    var row: Int
    var startCol: Int
    var cols: Int
    var text: String
    var foreground: TerminalRGBA
    var bold: Bool
    var lineCacheKey: TextLineCacheKey
}

struct TextLineCacheKey: Hashable {
    var bold: Bool
    var foregroundPackedValue: UInt32
    var text: String

    var estimatedCost: Int {
        max(64, text.utf16.count * 2)
    }
}

/// A block-element or box-drawing cell drawn as pixel-snapped rects instead of
/// a font glyph so adjacent cells tile without seams.
struct TerminalBlockGlyph: Equatable {
    var row: Int
    var col: Int
    var rects: [TerminalBlockRect]
    var foreground: TerminalRGBA
}

/// A box-drawing cell that can't be expressed as axis-aligned rects (rounded
/// corners, diagonals) and is stroked as a path at draw time, matching the
/// custom-drawn straight segments' stroke width.
struct TerminalStrokeGlyph: Equatable {
    var row: Int
    var col: Int
    var kind: TerminalBoxStrokeKind
    var character: Character
    var foreground: TerminalRGBA
}

/// The paint instructions for a single grid row, cached so unchanged rows are
/// reused across frames.
struct TerminalRowRenderPlan: Equatable {
    var backgroundRuns: [TerminalBackgroundRun]
    var textSegments: [TerminalTextSegment]
    var blockGlyphs: [TerminalBlockGlyph] = []
    var strokeGlyphs: [TerminalStrokeGlyph] = []
}

/// The cached paint instructions for a whole frame. Production drawing reads
/// row plans directly to avoid allocating a flattened copy after every update.
struct TerminalRenderPlan: Equatable {
    var rows: [TerminalRowRenderPlan]

    var backgroundRuns: [TerminalBackgroundRun] {
        rows.flatMap(\.backgroundRuns)
    }

    var textSegments: [TerminalTextSegment] {
        rows.flatMap(\.textSegments)
    }

    var blockGlyphs: [TerminalBlockGlyph] {
        rows.flatMap(\.blockGlyphs)
    }

    var strokeGlyphs: [TerminalStrokeGlyph] {
        rows.flatMap(\.strokeGlyphs)
    }

    static let empty = TerminalRenderPlan(rows: [])
}

/// How the most recent `update` rebuilt the plan — surfaced to the debug overlay
/// to validate that small changes only rebuild a few rows.
struct TerminalRenderPlanStats: Equatable {
    var wasFullRebuild: Bool
    var rebuiltRowCount: Int
    var totalRowCount: Int

    static let empty = TerminalRenderPlanStats(
        wasFullRebuild: false,
        rebuiltRowCount: 0,
        totalRowCount: 0
    )
}

/// Builds and caches per-row render plans, rebuilding only the rows the terminal
/// core flagged as damaged. A full rebuild happens when the render config or grid
/// dimensions change, or when the core reports full damage; otherwise only the
/// damaged rows are re-laid-out and the rest are reused.
final class TerminalRenderPlanCache {
    private(set) var plan = TerminalRenderPlan.empty
    private(set) var stats = TerminalRenderPlanStats.empty

    private var rows: [TerminalRowRenderPlan] = []
    private var cachedConfig: TerminalRenderConfig?
    private var cachedCols = 0
    private var cachedRows = 0

    /// Updates the cached plan for `frame`, rebuilding rows according to `damage`.
    func update(frame: TerminalFrame, renderConfig: TerminalRenderConfig, damage: TerminalDamage) {
        let configChanged = cachedConfig != renderConfig
        let dimensionsChanged = cachedCols != frame.cols
            || cachedRows != frame.rows
            || rows.count != frame.rows
        let forceFull = configChanged || dimensionsChanged || damage == .full

        if forceFull {
            rows = (0 ..< frame.rows).map { row in
                buildRow(row, frame: frame, renderConfig: renderConfig)
            }
            plan = TerminalRenderPlan(rows: rows)
            stats = TerminalRenderPlanStats(
                wasFullRebuild: true,
                rebuiltRowCount: frame.rows,
                totalRowCount: frame.rows
            )
        } else {
            let dirtyRows = dirtyRows(for: damage, rowCount: frame.rows)
            plan = .empty
            for row in dirtyRows {
                rows[row] = buildRow(row, frame: frame, renderConfig: renderConfig)
            }
            plan = TerminalRenderPlan(rows: rows)
            stats = TerminalRenderPlanStats(
                wasFullRebuild: false,
                rebuiltRowCount: dirtyRows.count,
                totalRowCount: frame.rows
            )
        }

        cachedConfig = renderConfig
        cachedCols = frame.cols
        cachedRows = frame.rows
    }

    private func dirtyRows(for damage: TerminalDamage, rowCount: Int) -> [Int] {
        guard case let .partial(spans) = damage else {
            return []
        }
        var seen = Set<Int>()
        var ordered: [Int] = []
        for span in spans where span.row >= 0 && span.row < rowCount {
            if seen.insert(span.row).inserted {
                ordered.append(span.row)
            }
        }
        return ordered
    }

    private func buildRow(
        _ row: Int,
        frame: TerminalFrame,
        renderConfig: TerminalRenderConfig
    ) -> TerminalRowRenderPlan {
        var backgroundRuns: [TerminalBackgroundRun] = []
        var textSegments: [TerminalTextSegment] = []
        var blockGlyphs: [TerminalBlockGlyph] = []
        var strokeGlyphs: [TerminalStrokeGlyph] = []

        var activeBackgroundRun: TerminalBackgroundRun?
        var text = ""
        var textForeground: TerminalRGBA?
        var textBold = false
        var textStartCol = 0
        var textCols = 0

        func flushBackgroundRun() {
            guard let run = activeBackgroundRun else {
                return
            }
            backgroundRuns.append(run)
            activeBackgroundRun = nil
        }

        func flushTextSegment() {
            guard let foreground = textForeground, !text.isEmpty else {
                return
            }
            textSegments.append(TerminalTextSegment(
                row: row,
                startCol: textStartCol,
                cols: textCols,
                text: text,
                foreground: foreground,
                bold: textBold,
                lineCacheKey: TextLineCacheKey(
                    bold: textBold,
                    foregroundPackedValue: foreground.packedValue,
                    text: text
                )
            ))
            text = ""
            textCols = 0
        }

        for cell in frame.cells(inRow: row) {
            if shouldPaintBackground(cell, renderConfig: renderConfig) {
                let opacity = backgroundOpacity(for: cell, renderConfig: renderConfig)
                if var run = activeBackgroundRun, run.canAppend(cell: cell, opacity: opacity) {
                    run.cols += 1
                    activeBackgroundRun = run
                } else {
                    flushBackgroundRun()
                    activeBackgroundRun = TerminalBackgroundRun(
                        row: row,
                        startCol: cell.col,
                        cols: 1,
                        color: cell.background,
                        opacity: opacity
                    )
                }
            } else {
                flushBackgroundRun()
            }

            guard cell.renderText else {
                flushTextSegment()
                textForeground = nil
                textBold = false
                continue
            }

            // Block elements and box-drawing connectors bypass the font: they
            // are drawn as pixel-snapped rects so adjacent cells tile without
            // seams (see TerminalBlockGlyphs / TerminalBoxDrawing).
            if let rects = TerminalBlockGlyphs.geometry(for: cell.character)
                ?? TerminalBoxDrawing.rectGeometry(
                    for: cell.character,
                    cellWidth: renderConfig.cellWidth,
                    cellHeight: renderConfig.cellHeight,
                    fontSize: renderConfig.fontSize
                )
            {
                flushTextSegment()
                textForeground = nil
                textBold = false
                blockGlyphs.append(TerminalBlockGlyph(
                    row: row,
                    col: cell.col,
                    rects: rects,
                    foreground: cell.foreground
                ))
                continue
            }

            // Rounded corners and diagonals are stroked as paths at draw time
            // so their stroke width matches the rect-drawn straight segments.
            if let kind = TerminalBoxDrawing.strokeKind(for: cell.character) {
                flushTextSegment()
                textForeground = nil
                textBold = false
                strokeGlyphs.append(TerminalStrokeGlyph(
                    row: row,
                    col: cell.col,
                    kind: kind,
                    character: cell.character,
                    foreground: cell.foreground
                ))
                continue
            }

            let foreground = cell.foreground
            let bold = cell.bold
            if textForeground != foreground || textBold != bold {
                flushTextSegment()
                textForeground = foreground
                textBold = bold
                textStartCol = cell.col
            }
            text.append(cell.character)
            textCols += 1
        }

        flushBackgroundRun()
        flushTextSegment()

        return TerminalRowRenderPlan(
            backgroundRuns: backgroundRuns,
            textSegments: textSegments,
            blockGlyphs: blockGlyphs,
            strokeGlyphs: strokeGlyphs
        )
    }

    private func shouldPaintBackground(
        _ cell: TerminalCell,
        renderConfig: TerminalRenderConfig
    ) -> Bool {
        !cell.usesTerminalDefaultBackground || renderConfig.backgroundOpacityCells
    }

    private func backgroundOpacity(
        for cell: TerminalCell,
        renderConfig: TerminalRenderConfig
    ) -> Double {
        cell.usesTerminalDefaultBackground ? renderConfig.backgroundOpacity : 1.0
    }
}
