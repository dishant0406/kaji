import AppKit
import CoreText
import SwiftUI

struct TerminalGridView: View {
    let frame: TerminalFrame
    let renderPlan: TerminalRenderPlan
    let renderDamage: TerminalDamage
    let selection: TerminalSelection?
    let renderConfig: TerminalRenderConfig
    let searchMatches: [TerminalSearchMatch]
    let activeSearchMatch: TerminalSearchMatch?
    var hoveredLink: TerminalFrameLink?
    let isFocused: Bool
    let isCursorVisible: Bool

    var body: some View {
        TerminalGridRepresentable(
            frame: frame,
            renderPlan: renderPlan,
            renderDamage: renderDamage,
            selection: selection,
            renderConfig: renderConfig,
            searchMatches: searchMatches,
            activeSearchMatch: activeSearchMatch,
            hoveredLink: hoveredLink,
            isFocused: isFocused,
            isCursorVisible: isCursorVisible
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }
}

private struct TerminalGridRepresentable: NSViewRepresentable {
    let frame: TerminalFrame
    let renderPlan: TerminalRenderPlan
    let renderDamage: TerminalDamage
    let selection: TerminalSelection?
    let renderConfig: TerminalRenderConfig
    let searchMatches: [TerminalSearchMatch]
    let activeSearchMatch: TerminalSearchMatch?
    var hoveredLink: TerminalFrameLink?
    let isFocused: Bool
    let isCursorVisible: Bool

    func makeNSView(context: Context) -> TerminalGridNSView {
        TerminalGridNSView()
    }

    func updateNSView(_ nsView: TerminalGridNSView, context: Context) {
        nsView.update(
            frame: frame,
            renderPlan: renderPlan,
            renderDamage: renderDamage,
            selection: selection,
            renderConfig: renderConfig,
            searchMatches: searchMatches,
            activeSearchMatch: activeSearchMatch,
            hoveredLink: hoveredLink,
            isFocused: isFocused,
            isCursorVisible: isCursorVisible
        )
    }
}

final class TerminalGridNSView: NSView {
    private var terminalFrame = TerminalFrame.empty
    private var renderPlan = TerminalRenderPlan.empty
    private var selection: TerminalSelection?
    private var renderConfig = TerminalRenderConfig.default
    private var searchMatches: [TerminalSearchMatch] = []
    private var activeSearchMatch: TerminalSearchMatch?
    private var hoveredLink: TerminalFrameLink?
    private var isTerminalFocused = false
    private var isCursorVisible = true

    // Per-frame draw caches. Building NSFonts, NSColors and (most expensively)
    // typeset CTLines per text segment on every `draw(_:)` dominated the render
    // cost while scrolling a full screen at 60 Hz; these memoize that work
    // across frames. The font and line caches are invalidated together whenever
    // the font family/size changes (`syncFonts`).
    private var cachedFontKey: FontKey?
    private var cachedRegularFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private var cachedBoldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
    private var nsColorCache: [UInt32: NSColor] = [:]
    private var alphaColorCache: [UInt64: NSColor] = [:]
    private let lineCache = TextLineCache()
    private var occlusionObserver: NotificationObserverToken?

    private struct FontKey: Equatable {
        var family: String
        var size: CGFloat
    }

    private struct DirtyGridBounds {
        var rows: ClosedRange<Int>
        var cols: ClosedRange<Int>

        func intersects(row: Int, startCol: Int, cols: Int) -> Bool {
            guard rows.contains(row), cols > 0 else {
                return false
            }
            let endCol = startCol + cols - 1
            return startCol <= self.cols.upperBound && endCol >= self.cols.lowerBound
        }
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        if let window, let superview {
            let windowPoint = superview.convert(point, to: nil)
            if !window.contentLayoutRect.contains(windowPoint) {
                return nil
            }
        }
        return super.hitTest(point)
    }

    /// Expose the visible grid as a text area so VoiceOver can read terminal
    /// output; the value is recomputed live from the current frame.
    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .textArea
    }

    override func accessibilityLabel() -> String? {
        "Terminal"
    }

    override func accessibilityValue() -> Any? {
        terminalFrame.visibleTextSnapshot()
    }

    override func accessibilitySelectedText() -> String? {
        terminalFrame.selectedText(for: selection)
    }

    override func accessibilityInsertionPointLineNumber() -> Int {
        terminalFrame.cursor?.row ?? 0
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }

    private func configureLayer() {
        wantsLayer = true
        layer?.isOpaque = false
        canDrawSubviewsIntoLayer = true
        // Live resize: redraw the grid on every resize step and keep stale
        // content anchored to the top-left while the next draw is pending,
        // instead of letting Core Animation stretch the previous frame across
        // the new bounds (the rubber-band look).
        layerContentsRedrawPolicy = .duringViewResize
        layerContentsPlacement = .topLeft
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        occlusionObserver = nil
        guard let window else {
            return
        }
        occlusionObserver = NotificationObserverToken(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let window = self.window else {
                        return
                    }
                    self.applyWindowOcclusion(visible: window.occlusionState.contains(.visible))
                }
            }
        )
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldSize = frame.size
        super.setFrameSize(newSize)
        guard oldSize != newSize else {
            return
        }
        invalidateBackingStoreForGeometryChange()
    }

    override func setBoundsSize(_ newSize: NSSize) {
        let oldSize = bounds.size
        super.setBoundsSize(newSize)
        guard oldSize != newSize else {
            return
        }
        invalidateBackingStoreForGeometryChange()
    }

    /// An occluded window (e.g. a background native tab) doesn't need this
    /// view's layer backing store — a full window-size retina bitmap that runs
    /// 10-25 MB per tab. Drop it and the typeset-line cache while hidden; the
    /// repaint on return rebuilds both.
    func applyWindowOcclusion(visible: Bool) {
        if visible {
            needsDisplay = true
        } else {
            layer?.contents = nil
            lineCache.removeAll()
        }
    }

    private func invalidateBackingStoreForGeometryChange() {
        layer?.contents = nil
        lineCache.removeAll()
        needsDisplay = true
        layer?.setNeedsDisplay()
    }

    func update(
        frame: TerminalFrame,
        renderPlan: TerminalRenderPlan,
        renderDamage: TerminalDamage,
        selection: TerminalSelection?,
        renderConfig: TerminalRenderConfig,
        searchMatches: [TerminalSearchMatch],
        activeSearchMatch: TerminalSearchMatch?,
        hoveredLink: TerminalFrameLink?,
        isFocused: Bool,
        isCursorVisible: Bool
    ) {
        let requiresFullRedraw = terminalFrame.cols != frame.cols
            || terminalFrame.rows != frame.rows
            || terminalFrame.displayOffset != frame.displayOffset
            || self.renderConfig != renderConfig
            || self.selection != selection
            || self.searchMatches != searchMatches
            || self.activeSearchMatch != activeSearchMatch
            || self.hoveredLink != hoveredLink
            || isTerminalFocused != isFocused

        self.terminalFrame = frame
        self.renderPlan = renderPlan
        self.selection = selection
        self.renderConfig = renderConfig
        self.searchMatches = searchMatches
        self.activeSearchMatch = activeSearchMatch
        self.hoveredLink = hoveredLink
        self.isTerminalFocused = isFocused
        self.isCursorVisible = isCursorVisible

        if requiresFullRedraw || renderDamage == .full {
            needsDisplay = true
            return
        }

        guard let dirtySpans = renderDamage.dirtySpans, !dirtySpans.isEmpty else {
            return
        }
        for span in dirtySpans {
            setNeedsDisplay(spanRect(span).insetBy(dx: -1, dy: -1))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard terminalFrame.cols > 0, terminalFrame.rows > 0 else {
            return
        }

        let dirtyBounds = dirtyGridBounds(for: dirtyRect)
        drawBackgrounds(in: dirtyRect, dirtyBounds: dirtyBounds)
        drawSearch(in: dirtyRect, dirtyBounds: dirtyBounds)
        drawSelection(in: dirtyRect, dirtyBounds: dirtyBounds)
        drawCursor(in: dirtyRect, dirtyBounds: dirtyBounds)
        drawBlockGlyphs(in: dirtyRect, dirtyBounds: dirtyBounds)
        drawStrokeGlyphs(in: dirtyRect, dirtyBounds: dirtyBounds)
        drawText(in: dirtyRect, dirtyBounds: dirtyBounds)
        drawHoveredLink(in: dirtyRect, dirtyBounds: dirtyBounds)
    }

    private var backingScale: CGFloat {
        max(1, window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1)
    }

    private func cellRect(col: Int, row: Int, cols: Int = 1) -> CGRect {
        CGRect(
            x: renderConfig.paddingX + CGFloat(col) * renderConfig.cellWidth,
            y: renderConfig.paddingY + CGFloat(row) * renderConfig.cellHeight,
            width: CGFloat(cols) * renderConfig.cellWidth,
            height: renderConfig.cellHeight
        ).pixelAligned(scale: backingScale)
    }

    private func rowRect(_ row: Int) -> CGRect {
        CGRect(
            x: 0,
            y: renderConfig.paddingY + CGFloat(row) * renderConfig.cellHeight,
            width: bounds.width,
            height: renderConfig.cellHeight
        )
    }

    private func spanRect(_ span: TerminalDirtySpan) -> CGRect {
        guard span.leftCol <= span.rightCol else {
            return rowRect(span.row)
        }
        return cellRect(
            col: max(0, span.leftCol),
            row: span.row,
            cols: max(1, span.rightCol - span.leftCol + 1)
        )
    }

    private func dirtyGridBounds(for dirtyRect: NSRect) -> DirtyGridBounds {
        let cellHeight = max(1, renderConfig.cellHeight)
        let cellWidth = max(1, renderConfig.cellWidth)
        let first = max(0, Int(floor((dirtyRect.minY - renderConfig.paddingY) / cellHeight)))
        let last = min(
            max(0, terminalFrame.rows - 1),
            Int(ceil((dirtyRect.maxY - renderConfig.paddingY) / cellHeight))
        )
        let firstCol = max(0, Int(floor((dirtyRect.minX - renderConfig.paddingX) / cellWidth)))
        let lastCol = min(
            max(0, terminalFrame.cols - 1),
            Int(ceil((dirtyRect.maxX - renderConfig.paddingX) / cellWidth))
        )
        return DirtyGridBounds(
            rows: first ... max(first, last),
            cols: firstCol ... max(firstCol, lastCol)
        )
    }

    private func rowIntersectsDirty(_ row: Int, _ dirtyBounds: DirtyGridBounds) -> Bool {
        dirtyBounds.rows.contains(row)
    }

    private func drawBackgrounds(in dirtyRect: NSRect, dirtyBounds: DirtyGridBounds) {
        for rowPlan in rowPlans(intersecting: dirtyBounds) {
            for run in rowPlan.backgroundRuns {
                guard dirtyBounds.intersects(row: run.row, startCol: run.startCol, cols: run.cols) else {
                    continue
                }
                let rect = cellRect(col: run.startCol, row: run.row, cols: run.cols)
                guard rect.intersects(dirtyRect) else {
                    continue
                }
                cachedNSColor(run.color, alpha: CGFloat(run.color.alpha * run.opacity)).setFill()
                fill(rect)
            }
        }
    }

    private func drawSelection(in dirtyRect: NSRect, dirtyBounds: DirtyGridBounds) {
        guard let ranges = selection?.rowRanges(cols: terminalFrame.cols, rows: terminalFrame.rows) else {
            return
        }
        NSColor.controlAccentColor.withAlphaComponent(0.35).setFill()
        for range in ranges where rowIntersectsDirty(range.row, dirtyBounds) {
            guard range.endCol >= range.startCol else {
                continue
            }
            guard dirtyBounds.intersects(
                row: range.row,
                startCol: range.startCol,
                cols: range.endCol - range.startCol + 1
            )
            else {
                continue
            }
            let rect = cellRect(
                col: range.startCol,
                row: range.row,
                cols: range.endCol - range.startCol + 1
            )
            guard rect.intersects(dirtyRect) else {
                continue
            }
            fill(rect)
        }
    }

    private func drawSearch(in dirtyRect: NSRect, dirtyBounds: DirtyGridBounds) {
        for match in searchMatches {
            guard let row = visibleSearchRow(for: match), rowIntersectsDirty(row, dirtyBounds) else {
                continue
            }
            guard dirtyBounds.intersects(
                row: row,
                startCol: match.startCol,
                cols: max(1, match.endCol - match.startCol + 1)
            )
            else {
                continue
            }
            let rect = cellRect(
                col: match.startCol,
                row: row,
                cols: max(1, match.endCol - match.startCol + 1)
            )
            guard rect.intersects(dirtyRect) else {
                continue
            }
            searchColor(for: match).setFill()
            fill(rect)
        }
    }

    private func visibleSearchRow(for match: TerminalSearchMatch) -> Int? {
        let visibleTop = terminalFrame.historySize - terminalFrame.displayOffset
        let row = match.row - visibleTop
        guard row >= 0, row < terminalFrame.rows else {
            return nil
        }
        return row
    }

    private func searchColor(for match: TerminalSearchMatch) -> NSColor {
        if match == activeSearchMatch {
            return NSColor.controlAccentColor.withAlphaComponent(0.42)
        }
        return NSColor.controlAccentColor.withAlphaComponent(0.18)
    }

    private func drawCursor(in dirtyRect: NSRect, dirtyBounds: DirtyGridBounds) {
        guard isTerminalFocused,
              isCursorVisible,
              let cursor = terminalFrame.cursor,
              terminalFrame.displayOffset == 0,
              dirtyBounds.intersects(row: cursor.row, startCol: cursor.col, cols: 1)
        else {
            return
        }

        let rect = cellRect(col: cursor.col, row: cursor.row)
        guard rect.intersects(dirtyRect) else {
            return
        }
        renderConfig.cursor.nsColor.setFill()
        switch cursor.style {
        case .block:
            fill(rect)
        case .line:
            fill(CGRect(x: rect.minX, y: rect.minY, width: min(2, rect.width), height: rect.height))
        }
    }

    /// Draws block-element and box-drawing cells as solid rects with every edge
    /// snapped to device pixels (see `TerminalBlockGlyphs.snappedRect` for the
    /// seam-free shared-boundary guarantee). Anti-aliasing is disabled so the
    /// axis-aligned fills keep hard edges, unlike font glyphs which only cover
    /// the font box inside the taller line-height cell.
    private func drawBlockGlyphs(in dirtyRect: NSRect, dirtyBounds: DirtyGridBounds) {
        let rowPlans = rowPlans(intersecting: dirtyBounds)
        guard rowPlans.contains(where: { !$0.blockGlyphs.isEmpty }) else {
            return
        }

        let context = NSGraphicsContext.current
        let previousShouldAntialias = context?.shouldAntialias ?? true
        context?.shouldAntialias = false
        defer { context?.shouldAntialias = previousShouldAntialias }

        for rowPlan in rowPlans {
            for glyph in rowPlan.blockGlyphs {
                guard dirtyBounds.intersects(row: glyph.row, startCol: glyph.col, cols: 1) else {
                    continue
                }
                for rect in glyph.rects {
                    guard let snapped = TerminalBlockGlyphs.snappedRect(
                        rect,
                        col: glyph.col,
                        row: glyph.row,
                        cellWidth: renderConfig.cellWidth,
                        cellHeight: renderConfig.cellHeight,
                        paddingX: renderConfig.paddingX,
                        paddingY: renderConfig.paddingY,
                        scale: backingScale
                    )
                    else {
                        continue
                    }
                    guard snapped.intersects(dirtyRect) else {
                        continue
                    }
                    cachedNSColor(glyph.foreground, alpha: CGFloat(glyph.foreground.alpha * rect.alpha)).setFill()
                    fill(snapped)
                }
            }
        }
    }

    /// Strokes rounded-corner (U+256D–U+2570) and diagonal (U+2571–U+2573)
    /// box-drawing glyphs as paths whose stroke width matches the rect-drawn
    /// straight segments, mirroring `paint_rounded_corner_path` /
    /// `paint_diagonal_path` in `crates/terminal_ui/src/grid.rs`. These stay
    /// anti-aliased — they are curves and slopes, not axis-aligned fills.
    private func drawStrokeGlyphs(in dirtyRect: NSRect, dirtyBounds: DirtyGridBounds) {
        let rowPlans = rowPlans(intersecting: dirtyBounds)
        guard rowPlans.contains(where: { !$0.strokeGlyphs.isEmpty }) else {
            return
        }

        let strokeWidth = TerminalBoxDrawing.strokeWidth(fontSize: renderConfig.fontSize)
        for rowPlan in rowPlans {
            for glyph in rowPlan.strokeGlyphs {
                guard dirtyBounds.intersects(row: glyph.row, startCol: glyph.col, cols: 1) else {
                    continue
                }
                guard let cell = TerminalBlockGlyphs.snappedRect(
                    TerminalBlockRect(left: 0, top: 0, right: 1, bottom: 1, alpha: 1),
                    col: glyph.col,
                    row: glyph.row,
                    cellWidth: renderConfig.cellWidth,
                    cellHeight: renderConfig.cellHeight,
                    paddingX: renderConfig.paddingX,
                    paddingY: renderConfig.paddingY,
                    scale: backingScale
                )
                else {
                    continue
                }
                guard cell.intersects(dirtyRect) else {
                    continue
                }

                cachedNSColor(glyph.foreground).setStroke()
                switch glyph.kind {
                case .roundedCorner:
                    strokeRoundedCorner(glyph.character, in: cell, strokeWidth: strokeWidth)
                case .diagonal:
                    strokeDiagonal(glyph.character, in: cell, strokeWidth: strokeWidth)
                }
            }
        }
    }

    /// Rounded corners: a short straight stub on each cell edge (aligned with
    /// adjacent straight box lines) connected by a quarter-circle cubic arc.
    private func strokeRoundedCorner(_ glyph: Character, in cell: CGRect, strokeWidth: CGFloat) {
        guard let spec = TerminalBoxDrawing.roundedCornerPathSpec(
            for: glyph,
            in: cell,
            strokeWidth: strokeWidth
        )
        else {
            return
        }

        let path = NSBezierPath()
        path.move(to: spec.start)
        path.line(to: spec.curveStart)
        path.curve(to: spec.curveEnd, controlPoint1: spec.controlA, controlPoint2: spec.controlB)
        path.line(to: spec.end)
        path.lineWidth = strokeWidth
        path.stroke()
    }

    /// Diagonals: stroked straight lines whose endpoints overshoot the cell
    /// boundary by a slope-dependent amount so adjacent diagonal cells join
    /// without pixel gaps.
    private func strokeDiagonal(_ glyph: Character, in cell: CGRect, strokeWidth: CGFloat) {
        guard cell.width > 0, cell.height > 0 else {
            return
        }
        let slopeX = 0.5 * min(cell.width / cell.height, 1)
        let slopeY = 0.5 * min(cell.height / cell.width, 1)

        let upperRightToLowerLeft = (
            CGPoint(x: cell.maxX + slopeX, y: cell.minY - slopeY),
            CGPoint(x: cell.minX - slopeX, y: cell.maxY + slopeY)
        )
        let upperLeftToLowerRight = (
            CGPoint(x: cell.minX - slopeX, y: cell.minY - slopeY),
            CGPoint(x: cell.maxX + slopeX, y: cell.maxY + slopeY)
        )

        let lines: [(CGPoint, CGPoint)]
        switch glyph {
        case "\u{2571}": lines = [upperRightToLowerLeft] // ╱
        case "\u{2572}": lines = [upperLeftToLowerRight] // ╲
        case "\u{2573}": lines = [upperRightToLowerLeft, upperLeftToLowerRight] // ╳
        default: return
        }

        for (start, end) in lines {
            let path = NSBezierPath()
            path.move(to: start)
            path.line(to: end)
            path.lineWidth = strokeWidth
            path.stroke()
        }
    }

    private func drawText(in dirtyRect: NSRect, dirtyBounds: DirtyGridBounds) {
        syncFonts()
        let regularFont = cachedRegularFont
        let boldFont = cachedBoldFont
        let baselineOffset = max(0, (renderConfig.cellHeight - regularFont.ascender + regularFont.descender) / 2)
            + regularFont.ascender

        let scale = backingScale
        guard let cgContext = NSGraphicsContext.current?.cgContext else {
            return
        }
        for rowPlan in rowPlans(intersecting: dirtyBounds) {
            for segment in rowPlan.textSegments {
                guard dirtyBounds.intersects(
                    row: segment.row,
                    startCol: segment.startCol,
                    cols: max(1, segment.cols)
                )
                else {
                    continue
                }
                let segmentRect = cellRect(
                    col: segment.startCol,
                    row: segment.row,
                    cols: max(1, segment.cols)
                )
                guard segmentRect.intersects(dirtyRect) else {
                    continue
                }
                let font = segment.bold ? boldFont : regularFont
                // Snap the glyph origin to device pixels so baselines land on
                // consistent pixel rows, matching the pixel-aligned backgrounds.
                let point = CGPoint(
                    x: ((renderConfig.paddingX + CGFloat(segment.startCol) * renderConfig.cellWidth)
                        * scale).rounded() / scale,
                    y: ((renderConfig.paddingY + CGFloat(segment.row) * renderConfig.cellHeight
                            + baselineOffset - font.ascender) * scale).rounded() / scale
                )
                let line = cachedLine(
                    text: segment.text,
                    bold: segment.bold,
                    foreground: segment.foreground,
                    font: font,
                    cacheKey: segment.lineCacheKey
                )
                // Draw the cached line at its baseline. The view is flipped, so
                // counter-flip locally (`scaleBy y: -1`) to keep glyphs upright;
                // `point.y` is the glyph-box top, so the baseline sits one
                // ascender below it — matching the previous `NSString.draw(at:)`.
                cgContext.saveGState()
                cgContext.textMatrix = .identity
                cgContext.translateBy(x: point.x, y: point.y + font.ascender)
                cgContext.scaleBy(x: 1, y: -1)
                CTLineDraw(line, cgContext)
                cgContext.restoreGState()
            }
        }
    }

    /// Returns the typeset line for `text`, building and caching it on first use.
    /// The cache key folds in weight and foreground color (both baked into the
    /// line's attributes) so a given styled run is typeset at most once; the
    /// cache is cleared when the font changes (`syncFonts`).
    private func cachedLine(
        text: String,
        bold: Bool,
        foreground: TerminalRGBA,
        font: NSFont,
        cacheKey: TextLineCacheKey
    ) -> CTLine {
        if let box = lineCache.object(forKey: cacheKey) {
            return box.line
        }
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: cachedNSColor(foreground),
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        lineCache.setObject(TextLineBox(line: line), forKey: cacheKey)
        return line
    }

    /// Rebuilds the cached regular/bold fonts when the font family or size
    /// changes, clearing the typeset-line cache (lines bake in the font).
    private func syncFonts() {
        let family = renderConfig.fontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = FontKey(family: family, size: renderConfig.fontSize)
        guard key != cachedFontKey else {
            return
        }
        cachedFontKey = key
        cachedRegularFont = terminalFont(weight: .regular)
        cachedBoldFont = terminalFont(weight: .semibold)
        lineCache.removeAll()
    }

    /// Memoizes the sRGB `NSColor` for a packed terminal color so identical
    /// colors aren't reallocated per cell/run/segment each draw.
    private func cachedNSColor(_ rgba: TerminalRGBA) -> NSColor {
        if let cached = nsColorCache[rgba.packedValue] {
            return cached
        }
        // Truecolor content can produce many distinct values; bound the cache.
        if nsColorCache.count >= 4096 {
            nsColorCache.removeAll(keepingCapacity: true)
        }
        let color = rgba.nsColor
        nsColorCache[rgba.packedValue] = color
        return color
    }

    private func cachedNSColor(_ rgba: TerminalRGBA, alpha: CGFloat) -> NSColor {
        let alpha = min(1, max(0, alpha))
        if abs(alpha - CGFloat(rgba.alpha)) <= 0.0001 {
            return cachedNSColor(rgba)
        }

        let alphaUnit = UInt64((alpha * 65535).rounded())
        let key = (UInt64(rgba.packedValue) << 16) | alphaUnit
        if let cached = alphaColorCache[key] {
            return cached
        }
        if alphaColorCache.count >= 4096 {
            alphaColorCache.removeAll(keepingCapacity: true)
        }
        let color = cachedNSColor(rgba).withAlphaComponent(alpha)
        alphaColorCache[key] = color
        return color
    }

    private func rowPlans(intersecting dirtyBounds: DirtyGridBounds) -> ArraySlice<TerminalRowRenderPlan> {
        guard !renderPlan.rows.isEmpty else {
            return []
        }
        let range = dirtyBounds.rows
        let lower = max(0, min(range.lowerBound, renderPlan.rows.count - 1))
        let upper = max(lower, min(range.upperBound, renderPlan.rows.count - 1))
        return renderPlan.rows[lower ... upper]
    }

    private func terminalFont(weight: NSFont.Weight) -> NSFont {
        let family = renderConfig.fontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        if !family.isEmpty, let font = NSFont(name: family, size: renderConfig.fontSize) {
            return weight == .semibold ? NSFontManager.shared.convertWeight(true, of: font) : font
        }
        return NSFont.monospacedSystemFont(ofSize: renderConfig.fontSize, weight: weight)
    }

    private func drawHoveredLink(in dirtyRect: NSRect, dirtyBounds: DirtyGridBounds) {
        guard let link = hoveredLink,
              link.row >= 0,
              link.row < terminalFrame.rows,
              dirtyBounds.intersects(row: link.row, startCol: link.startCol, cols: max(1, link.endCol - link.startCol + 1))
        else {
            return
        }

        let rect = cellRect(
            col: link.startCol,
            row: link.row,
            cols: max(1, link.endCol - link.startCol + 1)
        )
        let path = NSBezierPath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - 1))
        path.line(to: CGPoint(x: rect.maxX, y: rect.maxY - 1))
        path.lineWidth = 1
        renderConfig.foreground.nsColor.withAlphaComponent(0.85).setStroke()
        path.stroke()
    }

    private func fill(_ rect: CGRect) {
        rect.fill()
    }
}

/// Boxes a `CTLine` (a CoreFoundation type) so it can live in `NSCache`.
private final class TextLineBox {
    let line: CTLine
    init(line: CTLine) {
        self.line = line
    }
}

/// Bounded cache of typeset lines keyed by weight+color+text. `NSCache` evicts
/// under memory pressure and respects both entry and cost limits, so a
/// long-running session streaming varied long lines can't grow this without
/// bound.
private final class TextLineCache {
    private let cache = NSCache<TextLineCacheObjectKey, TextLineBox>()

    init() {
        cache.countLimit = 4096
        cache.totalCostLimit = 512 * 1024
    }

    func object(forKey key: TextLineCacheKey) -> TextLineBox? {
        cache.object(forKey: TextLineCacheObjectKey(key))
    }

    func setObject(_ object: TextLineBox, forKey key: TextLineCacheKey) {
        cache.setObject(
            object,
            forKey: TextLineCacheObjectKey(key),
            cost: key.estimatedCost
        )
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

/// Removes the wrapped NotificationCenter observer when released, so owners
/// don't have to touch the non-Sendable token from a nonisolated deinit.
private final class NotificationObserverToken: @unchecked Sendable {
    private let token: NSObjectProtocol

    init(_ token: NSObjectProtocol) {
        self.token = token
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}

private final class TextLineCacheObjectKey: NSObject {
    let key: TextLineCacheKey

    init(_ key: TextLineCacheKey) {
        self.key = key
    }

    override var hash: Int {
        key.hashValue
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? TextLineCacheObjectKey else {
            return false
        }
        return key == object.key
    }
}

private extension CGRect {
    func pixelAligned(scale: CGFloat) -> CGRect {
        let scale = max(1, scale)
        let minX = floor(self.minX * scale) / scale
        let minY = floor(self.minY * scale) / scale
        let maxX = ceil(self.maxX * scale) / scale
        let maxY = ceil(self.maxY * scale) / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
