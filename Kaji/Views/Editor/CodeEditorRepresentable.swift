import AppKit
import os
import SwiftUI

private final class CodeEditorTextView: NSTextView {
    private static let undoActionSelector = #selector(CodeEditorTextView.undo(_:))
    private static let redoActionSelector = #selector(CodeEditorTextView.redo(_:))

    var onUndoRequest: (() -> Bool)?
    var onRedoRequest: (() -> Bool)?
    var canUndoRequest: (() -> Bool)?
    var canRedoRequest: (() -> Bool)?
    var onKeyDownRequest: ((NSEvent) -> Bool)?

    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDownRequest?(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    @objc
    func undo(_ sender: Any?) {
        if onUndoRequest?() == true {
            return
        }
        undoManager?.undo()
    }

    @objc
    func redo(_ sender: Any?) {
        if onRedoRequest?() == true {
            return
        }
        undoManager?.redo()
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == Self.undoActionSelector, let canUndoRequest {
            return canUndoRequest()
        }
        if item.action == Self.redoActionSelector, let canRedoRequest {
            return canRedoRequest()
        }
        return super.validateUserInterfaceItem(item)
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        guard let layoutManager, let textContainer, let scrollView = enclosingScrollView else {
            super.scrollRangeToVisible(range)
            return
        }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.y += textContainerOrigin.y
        rect.origin.x += textContainerOrigin.x
        if let documentView = scrollView.documentView {
            rect = convert(rect, to: documentView)
        }

        let clipBounds = scrollView.contentView.bounds
        let visibleMinX = clipBounds.origin.x
        let visibleMaxX = visibleMinX + clipBounds.width
        let visibleMinY = clipBounds.origin.y
        let visibleMaxY = visibleMinY + clipBounds.height

        let cursorMinX = rect.origin.x
        let cursorMaxX = rect.origin.x + max(rect.width, 2)
        let cursorMinY = rect.origin.y
        let cursorMaxY = rect.origin.y + rect.height

        let maxScrollX: CGFloat = if let documentView = scrollView.documentView {
            max(0, documentView.bounds.width - clipBounds.width)
        } else {
            0
        }

        let maxScrollY: CGFloat = if let documentView = scrollView.documentView {
            max(0, documentView.bounds.height - clipBounds.height)
        } else {
            0
        }

        var newOrigin = clipBounds.origin

        if cursorMaxX > visibleMaxX {
            newOrigin.x = min(maxScrollX, max(0, cursorMaxX - clipBounds.width))
        } else if cursorMinX < visibleMinX {
            newOrigin.x = min(maxScrollX, max(0, cursorMinX))
        }

        if cursorMaxY > visibleMaxY {
            newOrigin.y = min(maxScrollY, max(0, cursorMaxY - clipBounds.height))
        } else if cursorMinY < visibleMinY {
            newOrigin.y = min(maxScrollY, max(0, cursorMinY))
        }

        if newOrigin != clipBounds.origin {
            scrollView.contentView.setBoundsOrigin(newOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}

private final class CodeEditorLayoutManager: NSLayoutManager {
    override func setGlyphs(
        _ glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: NSFont,
        forGlyphRange glyphRange: NSRange
    ) {
        guard aFont.isFixedPitch else {
            super.setGlyphs(glyphs, properties: props, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
            return
        }
        let mutableProps = UnsafeMutablePointer(mutating: props)
        for index in 0 ..< glyphRange.length {
            mutableProps[index].subtract(.elastic)
        }
        super.setGlyphs(glyphs, properties: mutableProps, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
    }
}

private enum CodeEditorMetrics {
    static let gutterWidth: CGFloat = 58
    static let gutterTextRightPadding: CGFloat = 12
    static let editorLeftPadding: CGFloat = 8
}

fileprivate struct CodeEditorAppearanceSnapshot: Equatable {
    let showsLineNumbers: Bool
    let highlightsActiveLine: Bool
    let showsIndentGuides: Bool
    let rendersWhitespace: Bool
    let highlightsMatchingBrackets: Bool
    let wordWrapEnabled: Bool
    let autoClosesPairs: Bool
    let autoIndentsNewLines: Bool
    let tabSize: Int

    @MainActor
    init(settings: EditorSettings) {
        showsLineNumbers = settings.showsLineNumbers
        highlightsActiveLine = settings.highlightsActiveLine
        showsIndentGuides = settings.showsIndentGuides
        rendersWhitespace = settings.rendersWhitespace
        highlightsMatchingBrackets = settings.highlightsMatchingBrackets
        wordWrapEnabled = settings.wordWrapEnabled
        autoClosesPairs = settings.autoClosesPairs
        autoIndentsNewLines = settings.autoIndentsNewLines
        tabSize = settings.tabSize
    }
}

final class ViewportContainerView: NSView {
    override var isFlipped: Bool { true }

    weak var textView: NSTextView?
    weak var viewport: ViewportState?
    var foldRegions: [EditorFoldRegion] = []
    var collapsedFoldRegionIDs: Set<String> = []
    var onToggleFold: ((EditorFoldRegion) -> Void)?
    fileprivate var editorAppearance = CodeEditorAppearanceSnapshot(settings: EditorSettings.shared)
    var activeGlobalLine = 0
    var lineStartOffsets: [Int] = [0]
    var matchingBracketLocalRanges: [NSRange] = []
    var diagnostics: [EditorDiagnostic] = []

    override func draw(_ dirtyRect: NSRect) {
        DebugFileLog.log(
            "EditorDraw",
            "draw start dirty=\(Self.describe(dirtyRect)) bounds=\(Self.describe(bounds)) viewport=\(viewport == nil ? "nil" : "set") activeLine=\(activeGlobalLine) lineOffsets=\(lineStartOffsets.count) bracketRanges=\(matchingBracketLocalRanges.count) settings=lineNumbers:\(editorAppearance.showsLineNumbers),activeLine:\(editorAppearance.highlightsActiveLine),indent:\(editorAppearance.showsIndentGuides),whitespace:\(editorAppearance.rendersWhitespace),brackets:\(editorAppearance.highlightsMatchingBrackets),tabSize:\(editorAppearance.tabSize)"
        )
        super.draw(dirtyRect)
        drawActiveLine(dirtyRect)
        drawIndentGuides(dirtyRect)
        drawWhitespace(dirtyRect)
        drawBracketHighlights(dirtyRect)
        drawDiagnosticGutterMarkers(dirtyRect)
        drawGutter(dirtyRect)
        drawFoldControls(dirtyRect)
        DebugFileLog.log("EditorDraw", "draw completed dirty=\(Self.describe(dirtyRect))")
    }

    override func mouseDown(with event: NSEvent) {
        DebugFileLog.log("EditorInput", "container mouseDown subviews=\(subviews.count) location=\(event.locationInWindow)")
        guard let textView = subviews.first as? NSTextView else {
            DebugFileLog.log("EditorInput", "container mouseDown missing textView")
            super.mouseDown(with: event)
            return
        }

        let pointInContainer = convert(event.locationInWindow, from: nil)
        if textView.frame.contains(pointInContainer) {
            DebugFileLog.log("EditorInput", "container mouseDown forwarded to textView point=\(pointInContainer)")
            super.mouseDown(with: event)
            return
        }

        if let region = foldRegion(at: pointInContainer) {
            onToggleFold?(region)
            return
        }

        let clampedX = min(pointInContainer.x, textView.frame.maxX - 1)
        let clampedY = min(max(pointInContainer.y, textView.frame.minY), textView.frame.maxY - 1)
        let pointInTextView = NSPoint(x: clampedX, y: clampedY - textView.frame.origin.y)
        let charIndex = textView.characterIndexForInsertion(at: pointInTextView)

        textView.window?.makeFirstResponder(textView)

        guard event.modifierFlags.contains(.shift) else {
            DebugFileLog.log("EditorInput", "container mouseDown set cursor charIndex=\(charIndex)")
            textView.setSelectedRange(NSRange(location: charIndex, length: 0))
            return
        }

        let current = textView.selectedRange()
        let anchor = current.location
        let newRange = if charIndex >= anchor {
            NSRange(location: anchor, length: charIndex - anchor)
        } else {
            NSRange(location: charIndex, length: anchor - charIndex)
        }
        textView.setSelectedRange(newRange)
        DebugFileLog.log("EditorInput", "container mouseDown set selection range=\(newRange)")
    }

    private var gutterWidth: CGFloat {
        editorAppearance.showsLineNumbers ? CodeEditorMetrics.gutterWidth : 0
    }

    private var textOriginX: CGFloat {
        gutterWidth + CodeEditorMetrics.editorLeftPadding
    }

    private func drawActiveLine(_ dirtyRect: NSRect) {
        guard editorAppearance.highlightsActiveLine, let viewport else {
            DebugFileLog.log("EditorDraw", "active line skipped enabled=\(editorAppearance.highlightsActiveLine) viewport=\(viewport == nil ? "nil" : "set")")
            return
        }
        guard viewport.isLineInViewport(activeGlobalLine) else {
            DebugFileLog.log("EditorDraw", "active line outside viewport active=\(activeGlobalLine) range=\(viewport.viewportStartLine)..<\(viewport.viewportEndLine)")
            return
        }
        let y = viewport.scrollY(forLine: activeGlobalLine)
        let rect = NSRect(x: 0, y: y, width: bounds.width, height: viewport.estimatedLineHeight)
        guard dirtyRect.intersects(rect) else { return }
        GhosttyService.shared.foregroundColor.withAlphaComponent(0.06).setFill()
        rect.fill()
    }

    private func drawGutter(_ dirtyRect: NSRect) {
        guard editorAppearance.showsLineNumbers, let viewport else {
            DebugFileLog.log("EditorDraw", "gutter skipped enabled=\(editorAppearance.showsLineNumbers) viewport=\(viewport == nil ? "nil" : "set")")
            return
        }
        let gutterRect = NSRect(x: 0, y: dirtyRect.minY, width: CodeEditorMetrics.gutterWidth, height: dirtyRect.height)
        GhosttyService.shared.backgroundColor.setFill()
        gutterRect.fill()
        GhosttyService.shared.foregroundColor.withAlphaComponent(0.08).setFill()
        NSRect(x: CodeEditorMetrics.gutterWidth - 1, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()

        guard let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular) as NSFont? else { return }
        let inactive = GhosttyService.shared.foregroundColor.withAlphaComponent(0.38)
        let active = GhosttyService.shared.foregroundColor.withAlphaComponent(0.78)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let first = max(viewport.viewportStartLine, Int(floor(dirtyRect.minY / viewport.estimatedLineHeight)) - 1)
        let last = min(viewport.viewportEndLine, Int(ceil(dirtyRect.maxY / viewport.estimatedLineHeight)) + 1)
        guard first < last else { return }
        DebugFileLog.log("EditorDraw", "gutter lines first=\(first) last=\(last) active=\(activeGlobalLine)")

        for line in first ..< last {
            let y = viewport.scrollY(forLine: line)
            let color = line == activeGlobalLine ? active : inactive
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ]
            let string = NSString(string: String(line + 1))
            let rect = NSRect(
                x: 0,
                y: y + max(0, (viewport.estimatedLineHeight - font.ascender + font.descender) / 2),
                width: CodeEditorMetrics.gutterWidth - CodeEditorMetrics.gutterTextRightPadding,
                height: viewport.estimatedLineHeight
            )
            string.draw(in: rect, withAttributes: attrs)
        }
    }

    private func drawDiagnosticGutterMarkers(_ dirtyRect: NSRect) {
        guard editorAppearance.showsLineNumbers, let viewport, !diagnostics.isEmpty else { return }
        for diagnostic in diagnostics {
            let line = diagnostic.line - 1
            guard viewport.isLineInViewport(line) else { continue }
            guard let localLine = viewport.viewportLine(forBackingStoreLine: line) else { continue }
            let y = CGFloat(localLine) * viewport.estimatedLineHeight
            let rect = NSRect(x: 6, y: y + 5, width: 6, height: 6)
            guard dirtyRect.intersects(rect) else { continue }
            diagnosticMarkerColor(diagnostic.severity).setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
    }

    private func diagnosticMarkerColor(_ severity: EditorDiagnosticSeverity) -> NSColor {
        switch severity {
        case .error: .systemRed
        case .warning: .systemYellow
        case .information: .systemBlue
        case .hint: GhosttyService.shared.foregroundColor.withAlphaComponent(0.5)
        }
    }

    private func drawFoldControls(_ dirtyRect: NSRect) {
        guard editorAppearance.showsLineNumbers, let viewport else { return }
        let visibleRegions = foldRegions.filter { viewport.isLineInViewport($0.startLine) }
        guard !visibleRegions.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: GhosttyService.shared.foregroundColor.withAlphaComponent(0.55),
        ]
        for region in visibleRegions {
            let y = viewport.scrollY(forLine: region.startLine)
            let rect = NSRect(x: CodeEditorMetrics.gutterWidth - 12, y: y, width: 10, height: viewport.estimatedLineHeight)
            guard dirtyRect.intersects(rect) else { continue }
            let symbol = collapsedFoldRegionIDs.contains(region.id) ? "›" : "⌄"
            NSString(string: symbol).draw(in: rect, withAttributes: attrs)
        }
    }

    private func foldRegion(at point: NSPoint) -> EditorFoldRegion? {
        guard editorAppearance.showsLineNumbers, let viewport, point.x >= CodeEditorMetrics.gutterWidth - 18, point.x <= CodeEditorMetrics.gutterWidth else { return nil }
        let line = Int(floor(point.y / viewport.estimatedLineHeight))
        return foldRegions.first { $0.startLine == line }
    }

    private func drawIndentGuides(_ dirtyRect: NSRect) {
        guard editorAppearance.showsIndentGuides, let textView, let viewport else {
            DebugFileLog.log("EditorDraw", "indent skipped enabled=\(editorAppearance.showsIndentGuides) textView=\(textView == nil ? "nil" : "set") viewport=\(viewport == nil ? "nil" : "set")")
            return
        }
        guard let font = textView.font else {
            DebugFileLog.log("EditorDraw", "indent skipped missing font")
            return
        }
        let tabSize = max(1, editorAppearance.tabSize)
        let unitWidth = font.maximumAdvancement.width > 0 ? font.maximumAdvancement.width : font.pointSize * 0.6
        let content = textView.string as NSString
        let guideColor = GhosttyService.shared.foregroundColor.withAlphaComponent(0.08)
        guideColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1

        enumerateVisibleLines(dirtyRect: dirtyRect, viewport: viewport, content: content) { _, globalLine, lineRange in
            let line = content.substring(with: lineRange)
            let indentColumns = indentationColumns(in: line, tabSize: tabSize)
            guard indentColumns >= tabSize else { return }
            let y = viewport.scrollY(forLine: globalLine)
            let lineTop = max(y, dirtyRect.minY)
            let lineBottom = min(y + viewport.estimatedLineHeight, dirtyRect.maxY)
            guard lineTop < lineBottom else { return }
            for column in stride(from: tabSize, through: indentColumns, by: tabSize) {
                let x = textOriginX + CGFloat(column) * unitWidth
                path.move(to: NSPoint(x: x, y: lineTop))
                path.line(to: NSPoint(x: x, y: lineBottom))
            }
        }
        path.stroke()
        DebugFileLog.log("EditorDraw", "indent completed contentLength=\(content.length) tabSize=\(tabSize)")
    }

    private func drawWhitespace(_ dirtyRect: NSRect) {
        guard editorAppearance.rendersWhitespace, let textView, let viewport else {
            DebugFileLog.log("EditorDraw", "whitespace skipped enabled=\(editorAppearance.rendersWhitespace) textView=\(textView == nil ? "nil" : "set") viewport=\(viewport == nil ? "nil" : "set")")
            return
        }
        guard let font = textView.font else {
            DebugFileLog.log("EditorDraw", "whitespace skipped missing font")
            return
        }
        let content = textView.string as NSString
        let unitWidth = font.maximumAdvancement.width > 0 ? font.maximumAdvancement.width : font.pointSize * 0.6
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: GhosttyService.shared.foregroundColor.withAlphaComponent(0.23),
        ]
        enumerateVisibleLines(dirtyRect: dirtyRect, viewport: viewport, content: content) { _, globalLine, lineRange in
            let line = content.substring(with: lineRange)
            let baselineY = viewport.scrollY(forLine: globalLine) + max(0, (viewport.estimatedLineHeight - font.ascender + font.descender) / 2)
            var column = 0
            for character in line {
                if character == " " {
                    NSString(string: "\u{00B7}").draw(at: NSPoint(x: textOriginX + CGFloat(column) * unitWidth, y: baselineY), withAttributes: attrs)
                    column += 1
                } else if character == "\t" {
                    NSString(string: "\u{2192}").draw(at: NSPoint(x: textOriginX + CGFloat(column) * unitWidth, y: baselineY), withAttributes: attrs)
                    column += max(1, editorAppearance.tabSize - column % max(1, editorAppearance.tabSize))
                } else {
                    column += 1
                }
            }
        }
        DebugFileLog.log("EditorDraw", "whitespace completed contentLength=\(content.length)")
    }

    private func drawBracketHighlights(_ dirtyRect: NSRect) {
        guard editorAppearance.highlightsMatchingBrackets, let textView else {
            DebugFileLog.log("EditorDraw", "brackets skipped enabled=\(editorAppearance.highlightsMatchingBrackets) textView=\(textView == nil ? "nil" : "set")")
            return
        }
        guard !matchingBracketLocalRanges.isEmpty,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else {
            DebugFileLog.log("EditorDraw", "brackets skipped ranges=\(matchingBracketLocalRanges.count) layout=\(textView.layoutManager == nil ? "nil" : "set") container=\(textView.textContainer == nil ? "nil" : "set")")
            return
        }
        let fill = (GhosttyService.shared.paletteColor(at: 4) ?? GhosttyService.shared.foregroundColor).withAlphaComponent(0.18)
        let stroke = (GhosttyService.shared.paletteColor(at: 4) ?? GhosttyService.shared.foregroundColor).withAlphaComponent(0.46)
        for range in matchingBracketLocalRanges {
            DebugFileLog.log("EditorDraw", "bracket draw range=\(range) storageLength=\(textView.string.count)")
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += textView.frame.origin.x + textView.textContainerOrigin.x
            rect.origin.y += textView.frame.origin.y + textView.textContainerOrigin.y
            rect = rect.insetBy(dx: -1, dy: -1)
            guard dirtyRect.intersects(rect) else { continue }
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            fill.setFill()
            path.fill()
            stroke.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func enumerateVisibleLines(
        dirtyRect: NSRect,
        viewport: ViewportState,
        content: NSString,
        body: (Int, Int, NSRange) -> Void
    ) {
        let firstGlobal = max(viewport.viewportStartLine, Int(floor(dirtyRect.minY / viewport.estimatedLineHeight)) - 1)
        let lastGlobal = min(viewport.viewportEndLine, Int(ceil(dirtyRect.maxY / viewport.estimatedLineHeight)) + 1)
        guard firstGlobal < lastGlobal else {
            DebugFileLog.log("EditorDraw", "enumerate lines empty first=\(firstGlobal) last=\(lastGlobal) dirty=\(Self.describe(dirtyRect))")
            return
        }
        DebugFileLog.log("EditorDraw", "enumerate lines first=\(firstGlobal) last=\(lastGlobal) contentLength=\(content.length)")
        for globalLine in firstGlobal ..< lastGlobal {
            guard let localLine = viewport.viewportLine(forBackingStoreLine: globalLine) else { continue }
            let location = lineStartLocation(localLine: localLine, content: content)
            guard location <= content.length else {
                DebugFileLog.log("EditorDraw", "line location out of bounds local=\(localLine) global=\(globalLine) location=\(location) contentLength=\(content.length) offsets=\(lineStartOffsets.count)")
                continue
            }
            let rawRange = content.lineRange(for: NSRange(location: location, length: 0))
            let excludesNewline = NSMaxRange(rawRange) < content.length ? rawRange.length - 1 : rawRange.length
            body(localLine, globalLine, NSRange(location: rawRange.location, length: max(0, excludesNewline)))
        }
    }

    private func lineStartLocation(localLine: Int, content: NSString) -> Int {
        guard localLine >= 0, localLine < lineStartOffsets.count else {
            DebugFileLog.log("EditorDraw", "missing line offset local=\(localLine) offsets=\(lineStartOffsets.count) contentLength=\(content.length)")
            return content.length
        }
        return lineStartOffsets[localLine]
    }

    private static func describe(_ rect: NSRect) -> String {
        "x=\(rect.origin.x),y=\(rect.origin.y),w=\(rect.width),h=\(rect.height)"
    }

    private func indentationColumns(in line: String, tabSize: Int) -> Int {
        var columns = 0
        for character in line {
            if character == " " {
                columns += 1
            } else if character == "\t" {
                columns += max(1, tabSize - columns % tabSize)
            } else {
                break
            }
        }
        return columns
    }
}

struct CodeEditorView: NSViewRepresentable {
    @Bindable var state: EditorTabState
    let typography: AppTypographySettings
    let themeVersion: Int
    let showsVerticalScroller: Bool
    let focused: Bool
    let searchNeedle: String
    let searchNavigationVersion: Int
    let searchNavigationDirection: EditorSearchNavigationDirection
    let searchCaseSensitive: Bool
    let searchUseRegex: Bool
    let replaceText: String
    let replaceVersion: Int
    let replaceAllVersion: Int
    let editorFocusVersion: Int
    let symbolNavigationVersion: Int
    let lineNavigationVersion: Int
    let inlineEditRequestVersion: Int
    let inlineEditApplyVersion: Int
    let lspChangeVersion: Int
    let onFocus: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, typography: typography)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = showsVerticalScroller
        scrollView.hasHorizontalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        let textStorage = NSTextStorage()
        let layoutManager = CodeEditorLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ))
        textContainer.widthTracksTextView = false
        textContainer.lineFragmentPadding = 8
        layoutManager.addTextContainer(textContainer)

        let textView = CodeEditorTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize), textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView

        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 4)

        let font = typography.nsFont(size: AppTypographySettings.defaultFontSize)
        textView.font = font
        textView.backgroundColor = GhosttyService.shared.backgroundColor
        textView.insertionPointColor = GhosttyService.shared.foregroundColor
        textView.textColor = GhosttyService.shared.foregroundColor
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: GhosttyService.shared.foregroundColor,
        ]
        textView.selectedTextAttributes = [
            .backgroundColor: GhosttyService.shared.foregroundColor.withAlphaComponent(0.15),
        ]

        scrollView.autohidesScrollers = showsVerticalScroller
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true

        let coordinator = context.coordinator
        textView.delegate = coordinator
        coordinator.textView = textView
        coordinator.scrollView = scrollView
        textView.onUndoRequest = { [weak coordinator] in
            coordinator?.performUndoRequest() ?? false
        }
        textView.onRedoRequest = { [weak coordinator] in
            coordinator?.performRedoRequest() ?? false
        }
        textView.canUndoRequest = { [weak coordinator] in
            coordinator?.canPerformUndoRequest() ?? false
        }
        textView.canRedoRequest = { [weak coordinator] in
            coordinator?.canPerformRedoRequest() ?? false
        }
        textView.onKeyDownRequest = { [weak coordinator] event in
            coordinator?.handleKeyDown(event) ?? false
        }
        coordinator.setScrollObserver(for: scrollView)
        textView.undoManager?.removeAllActions()

        return scrollView
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        if let textView = coordinator.textView {
            textView.undoManager?.removeAllActions()
            if let window = textView.window, window.firstResponder === textView {
                window.makeFirstResponder(nil)
            }
            if let codeTextView = textView as? CodeEditorTextView {
                codeTextView.onUndoRequest = nil
                codeTextView.onRedoRequest = nil
                codeTextView.canUndoRequest = nil
                codeTextView.canRedoRequest = nil
                codeTextView.onKeyDownRequest = nil
            }
        }
        coordinator.textView?.delegate = nil
    }

    private static func claimFirstResponder(textView: NSTextView, attemptsRemaining: Int) {
        guard attemptsRemaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak textView] in
            guard let textView else { return }
            guard let window = textView.window else {
                claimFirstResponder(textView: textView, attemptsRemaining: attemptsRemaining - 1)
                return
            }
            window.makeFirstResponder(textView)
        }
    }

    private static func tabInterval(for tabSize: Int) -> CGFloat {
        let font = AppTypographySettings.shared.nsFont(size: AppTypographySettings.defaultFontSize)
        let characterWidth = max(font.maximumAdvancement.width, font.pointSize * 0.6)
        return characterWidth * CGFloat(max(1, tabSize))
    }

    // MARK: - updateNSView

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let coordinator = context.coordinator

        if scrollView.hasVerticalScroller != showsVerticalScroller {
            scrollView.hasVerticalScroller = showsVerticalScroller
            scrollView.autohidesScrollers = showsVerticalScroller
        }

        if state.backingStore != nil, coordinator.viewportState == nil {
            coordinator.enterViewportMode(scrollView: scrollView)
        }

        updateNSViewViewportMode(scrollView: scrollView, textView: textView, coordinator: coordinator)
    }

    // MARK: - Viewport Mode

    private func updateNSViewViewportMode(scrollView: NSScrollView, textView: NSTextView, coordinator: Coordinator) {
        guard let viewport = coordinator.viewportState else { return }

        let backingStoreChanged = coordinator.lastSyncedBackingStoreVersion != state.backingStoreVersion
        if backingStoreChanged {
            coordinator.lastSyncedBackingStoreVersion = state.backingStoreVersion
            coordinator.invalidateRenderedViewportText()
            coordinator.clearViewportHistory()
        }

        let incrementalFinished = coordinator.wasIncrementalLoading && !state.isIncrementalLoading
        coordinator.wasIncrementalLoading = state.isIncrementalLoading

        if backingStoreChanged || incrementalFinished {
            coordinator.updateContainerHeight()
            coordinator.updateMarkdownEditorScrollMetrics()
        }

        if !coordinator.hasAppliedInitialContent, viewport.backingStore.lineCount > 1 || backingStoreChanged {
            coordinator.hasAppliedInitialContent = true
            coordinator.refreshViewport(force: true)
            if focused {
                Self.claimFirstResponder(textView: textView, attemptsRemaining: 20)
            }
        }

        let themeChanged = coordinator.lastThemeVersion != themeVersion
        let font = typography.nsFont(size: AppTypographySettings.defaultFontSize)
        let fontChanged = textView.font != font
        let appearance = CodeEditorAppearanceSnapshot(settings: EditorSettings.shared)
        let appearanceChanged = coordinator.lastAppearance != appearance

        applyThemeAndFont(textView: textView, font: font)
        applyEditorAppearance(textView: textView, coordinator: coordinator, appearance: appearance)

        if fontChanged || appearanceChanged {
            viewport.updateEstimatedLineHeight(font: font)
            viewport.updateDocumentPadding(
                topInset: textView.textContainerInset.height,
                bottomInset: textView.textContainerInset.height
            )
            coordinator.updateContainerHeight()
            coordinator.updateMarkdownEditorScrollMetrics()
            coordinator.refreshViewport(force: true)
        }

        if themeChanged, !fontChanged, !appearanceChanged {
            coordinator.refreshViewport(force: true)
        }

        if themeChanged {
            coordinator.applySearchHighlights(force: true)
            coordinator.lastThemeVersion = themeVersion
        }

        updateSearchViewport(coordinator: coordinator)
        coordinator.syncMarkdownScrollPositionIfNeeded()
        coordinator.updateMarkdownEditorScrollMetrics()

        if coordinator.lastEditorFocusVersion != editorFocusVersion {
            coordinator.lastEditorFocusVersion = editorFocusVersion
            coordinator.focusEditorPreservingSelection()
        }

        if coordinator.lastSymbolNavigationVersion != symbolNavigationVersion {
            coordinator.lastSymbolNavigationVersion = symbolNavigationVersion
            coordinator.navigateToRequestedSymbol()
        }

        if coordinator.lastLineNavigationVersion != lineNavigationVersion {
            coordinator.lastLineNavigationVersion = lineNavigationVersion
            coordinator.navigateToRequestedLine()
        }

        if coordinator.lastInlineEditRequestVersion != inlineEditRequestVersion {
            coordinator.lastInlineEditRequestVersion = inlineEditRequestVersion
            coordinator.prepareInlineEdit()
        }

        if coordinator.lastInlineEditApplyVersion != inlineEditApplyVersion {
            coordinator.lastInlineEditApplyVersion = inlineEditApplyVersion
            coordinator.applyInlineEditProposal()
        }

        if coordinator.lastLSPChangeVersion != lspChangeVersion {
            coordinator.lastLSPChangeVersion = lspChangeVersion
            coordinator.scheduleLSPChange()
        }
    }

    // MARK: - Shared helpers

    private func applyThemeAndFont(textView: NSTextView, font: NSFont) {
        let fgColor = GhosttyService.shared.foregroundColor
        let bgColor = GhosttyService.shared.backgroundColor

        if textView.backgroundColor != bgColor {
            textView.backgroundColor = bgColor
        }
        if textView.insertionPointColor != fgColor {
            textView.insertionPointColor = fgColor
        }
        if textView.textColor != fgColor {
            textView.textColor = fgColor
        }

        if (textView.typingAttributes[.foregroundColor] as? NSColor) != fgColor {
            textView.typingAttributes[.foregroundColor] = fgColor
        }

        if textView.font != font {
            textView.font = font
            textView.typingAttributes[.font] = font
        }

        let selectionBackground = fgColor.withAlphaComponent(0.15)
        if let selectedBg = textView.selectedTextAttributes[.backgroundColor] as? NSColor, selectedBg != selectionBackground {
            textView.selectedTextAttributes = [
                .backgroundColor: selectionBackground,
            ]
        }
    }

    private func applyEditorAppearance(
        textView: NSTextView,
        coordinator: Coordinator,
        appearance: CodeEditorAppearanceSnapshot
    ) {
        coordinator.lastAppearance = appearance
        let insetWidth = (appearance.showsLineNumbers ? CodeEditorMetrics.gutterWidth : 0) + CodeEditorMetrics.editorLeftPadding
        let inset = NSSize(width: insetWidth, height: 4)
        if textView.textContainerInset != inset {
            textView.textContainerInset = inset
        }
        if let textContainer = textView.textContainer {
            let tabInterval = Self.tabInterval(for: appearance.tabSize)
            textView.defaultParagraphStyle = Self.paragraphStyle(tabInterval: tabInterval)
            textView.typingAttributes[.paragraphStyle] = Self.paragraphStyle(tabInterval: tabInterval)
            textContainer.lineFragmentPadding = 8
            if appearance.wordWrapEnabled, let scrollView = coordinator.scrollView {
                textContainer.widthTracksTextView = true
                textContainer.containerSize = NSSize(
                    width: max(1, scrollView.contentSize.width),
                    height: CGFloat.greatestFiniteMagnitude
                )
                textView.isHorizontallyResizable = false
                textView.autoresizingMask = [.width]
                scrollView.hasHorizontalScroller = false
            } else {
                textContainer.widthTracksTextView = false
                textContainer.containerSize = NSSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                )
                textView.isHorizontallyResizable = true
                textView.autoresizingMask = []
                coordinator.scrollView?.hasHorizontalScroller = true
            }
        }
        coordinator.containerView?.editorAppearance = appearance
        coordinator.refreshEditorDecorations()
    }

    private static func paragraphStyle(tabInterval: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.defaultTabInterval = tabInterval
        style.tabStops = (1 ... 80).map { NSTextTab(textAlignment: .left, location: CGFloat($0) * tabInterval) }
        return style
    }

    private func updateSearchViewport(coordinator: Coordinator) {
        if !state.searchVisible, coordinator.lastSearchVisible {
            coordinator.lastSearchVisible = false
            coordinator.clearSearchHighlights()
            return
        }

        let becameVisible = state.searchVisible && !coordinator.lastSearchVisible
        coordinator.lastSearchVisible = state.searchVisible

        let searchOptionsChanged = coordinator.lastSearchCaseSensitive != searchCaseSensitive
            || coordinator.lastSearchUseRegex != searchUseRegex
        if coordinator.lastSearchNeedle != searchNeedle || searchOptionsChanged || becameVisible {
            coordinator.lastSearchNeedle = searchNeedle
            coordinator.lastSearchCaseSensitive = searchCaseSensitive
            coordinator.lastSearchUseRegex = searchUseRegex
            coordinator.performSearchViewport(searchNeedle, caseSensitive: searchCaseSensitive, useRegex: searchUseRegex)
        }

        if coordinator.lastSearchNavigationVersion != searchNavigationVersion {
            coordinator.lastSearchNavigationVersion = searchNavigationVersion
            coordinator.navigateSearchViewport(forward: searchNavigationDirection == .next)
        }

        if coordinator.lastReplaceVersion != replaceVersion {
            coordinator.lastReplaceVersion = replaceVersion
            coordinator.replaceCurrentViewport(
                with: replaceText,
                needle: searchNeedle,
                caseSensitive: searchCaseSensitive,
                useRegex: searchUseRegex
            )
        }

        if coordinator.lastReplaceAllVersion != replaceAllVersion {
            coordinator.lastReplaceAllVersion = replaceAllVersion
            coordinator.replaceAllViewport(
                with: replaceText,
                needle: searchNeedle,
                caseSensitive: searchCaseSensitive,
                useRegex: searchUseRegex
            )
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private struct ViewportCursor {
            let line: Int
            let column: Int
        }

        private struct PendingViewportEdit {
            let startLine: Int
            let oldLines: [String]
            let newLines: [String]
            let selectionBefore: ViewportCursor
        }

        private struct ViewportEdit {
            let startLine: Int
            let oldLines: [String]
            let newLines: [String]
            let selectionBefore: ViewportCursor
            let selectionAfter: ViewportCursor
        }

        private struct ViewportEditGroup {
            var edits: [ViewportEdit]
        }

        let state: EditorTabState
        let typography: AppTypographySettings
        weak var textView: NSTextView?

        weak var scrollView: NSScrollView?
        var viewportState: ViewportState?
        var containerView: ViewportContainerView?

        var isUpdating = false
        private var isEditingViewport = false
        var hasAppliedInitialContent = false
        var lastThemeVersion = -1
        var lastSearchVisible = false
        var lastSearchNeedle = ""
        var lastSearchNavigationVersion = -1
        var lastSearchCaseSensitive = false
        var lastSearchUseRegex = false
        var lastReplaceVersion = 0
        var lastReplaceAllVersion = 0
        var lastEditorFocusVersion = 0
        var lastSymbolNavigationVersion = 0
        var lastLineNavigationVersion = 0
        var lastInlineEditRequestVersion = 0
        var lastInlineEditApplyVersion = 0
        var lastLSPChangeVersion = 0
        var lastSyncedBackingStoreVersion = -1
        fileprivate var lastAppearance = CodeEditorAppearanceSnapshot(settings: EditorSettings.shared)
        var wasIncrementalLoading = false
        private static let initialViewportLineLimit = 1100
        private(set) var lineStartOffsets: [Int] = [0]
        private weak var observedContentView: NSClipView?
        private static let viewportUndoLimit = 200
        private static let viewportUndoCoalesceInterval: CFTimeInterval = 1.0
        private static let undoCommandSelector = #selector(CodeEditorTextView.undo(_:))
        private static let redoCommandSelector = #selector(CodeEditorTextView.redo(_:))
        private static let previewRefreshDebounceNanos: UInt64 = 500_000_000
        private static let lspChangeDebounceNanos: UInt64 = 180_000_000
        private static let indentCommandSelector = #selector(NSResponder.insertTab(_:))
        private static let outdentCommandSelector = #selector(NSResponder.insertBacktab(_:))
        private static let newlineCommandSelector = #selector(NSResponder.insertNewline(_:))
        private static let moveToBeginningOfLineSelector = #selector(NSResponder.moveToBeginningOfLine(_:))
        private static let moveToEndOfLineSelector = #selector(NSResponder.moveToEndOfLine(_:))
        private static let deleteBackwardSelector = #selector(NSResponder.deleteBackward(_:))
        private static let perfLogger = Logger(subsystem: "app.kaji", category: "EditorPerf")
        private static let perfEnabled: Bool = {
            if let env = ProcessInfo.processInfo.environment["KAJI_EDITOR_PERF"] {
                let value = env.lowercased()
                return value == "1" || value == "true" || value == "yes"
            }
            return UserDefaults.standard.bool(forKey: "KajiEditorPerf")
        }()

        private var pendingViewportEdit: PendingViewportEdit?
        private var viewportUndoStack: [ViewportEditGroup] = []
        private var viewportRedoStack: [ViewportEditGroup] = []
        private var lastViewportEditTimestamp: CFTimeInterval?
        private var isApplyingViewportHistory = false
        private var needsViewportTextReload = true
        private var lastRenderedViewportRange: Range<Int>?
        private var lastRenderedBackingStoreVersion = -1
        private var lastObservedClipSize: CGSize = .zero
        private var isApplyingMarkdownScroll = false
        private var refreshTimingCount = 0
        private var highlightTimingCount = 0
        private var lastRefreshDurationMs: Double = 0
        private var lastHighlightDurationMs: Double = 0
        private var previewRefreshTask: Task<Void, Never>?
        private var lspChangeTask: Task<Void, Never>?
        private var pendingScrollRefreshTask: Task<Void, Never>?
        private var lastDiagnosticFingerprint = ""
        private var lastDiagnosticViewportRange: Range<Int> = 0 ..< 0
        private var isScrollDrivenRefresh = false
        private var pendingCascadeReapplyGeneration: UInt64 = 0
        private let filePathForLogging: String

        init(state: EditorTabState, typography: AppTypographySettings) {
            self.state = state
            self.typography = typography
            filePathForLogging = state.filePath
            super.init()
            DebugFileLog.log("EditorCoordinator", "init filePath=\(state.filePath)")
        }

        deinit {
            DebugFileLog.log("EditorCoordinator", "deinit filePath=\(filePathForLogging)")
            previewRefreshTask?.cancel()
            lspChangeTask?.cancel()
            pendingScrollRefreshTask?.cancel()
            NotificationCenter.default.removeObserver(self)
        }

        private func beginPerfTiming() -> CFTimeInterval? {
            guard Self.perfEnabled else { return nil }
            return CACurrentMediaTime()
        }

        func invalidateRenderedViewportText() {
            DebugFileLog.log("EditorViewport", "invalidateRenderedViewportText filePath=\(state.filePath)")
            needsViewportTextReload = true
        }

        private func recordRefreshTiming(start: CFTimeInterval?, durationLineCount: Int, force: Bool) {
            guard let start else { return }
            let durationMs = (CACurrentMediaTime() - start) * 1000
            let deltaMs = durationMs - lastRefreshDurationMs
            lastRefreshDurationMs = durationMs
            refreshTimingCount += 1
            if refreshTimingCount.isMultiple(of: 24) || durationMs >= 3 {
                Self.perfLogger.debug(
                    "refresh ms \(durationMs) delta \(deltaMs) force \(force) lines \(durationLineCount)"
                )
            }
        }

        private func recordHighlightTiming(start: CFTimeInterval?, highlightedRangeCount: Int, force: Bool) {
            guard let start else { return }
            let durationMs = (CACurrentMediaTime() - start) * 1000
            let deltaMs = durationMs - lastHighlightDurationMs
            lastHighlightDurationMs = durationMs
            highlightTimingCount += 1
            if highlightTimingCount.isMultiple(of: 30) || durationMs >= 2 {
                Self.perfLogger.debug(
                    "highlight ms \(durationMs) delta \(deltaMs) force \(force) ranges \(highlightedRangeCount)"
                )
            }
        }

        func refreshEditorDecorations() {
            guard let viewport = viewportState else {
                DebugFileLog.log("EditorDecorations", "refresh skipped missing viewport filePath=\(state.filePath)")
                return
            }
            DebugFileLog.log(
                "EditorDecorations",
                "refresh filePath=\(state.filePath) activeLine=\(state.cursorLine) viewport=\(viewport.viewportStartLine)..<\(viewport.viewportEndLine) offsets=\(lineStartOffsets.count) textLength=\(textView?.string.count ?? -1) container=\(containerView == nil ? "nil" : "set")"
            )
            containerView?.textView = textView
            containerView?.viewport = viewport
            containerView?.activeGlobalLine = max(0, state.cursorLine - 1)
            containerView?.lineStartOffsets = lineStartOffsets
            containerView?.matchingBracketLocalRanges = matchingBracketRanges()
            containerView?.foldRegions = state.foldRegions()
            containerView?.diagnostics = DiagnosticsStore.shared.diagnostics(for: state.filePath)
            containerView?.collapsedFoldRegionIDs = state.collapsedFoldRegionIDs
            containerView?.onToggleFold = { [weak self] region in
                self?.toggleFold(region)
            }
            containerView?.layer?.backgroundColor = GhosttyService.shared.backgroundColor.cgColor
            containerView?.needsDisplay = true
        }

        private func toggleFold(_ region: EditorFoldRegion) {
            state.toggleFoldRegion(region)
            viewportState?.rebuildVisualLines(collapsedRegions: state.foldRegions().filter { state.isFoldRegionCollapsed($0) })
            invalidateRenderedViewportText()
            updateContainerHeight()
            refreshViewport(force: true)
            refreshEditorDecorations()
            ToastState.shared.show(state.isFoldRegionCollapsed(region) ? "Folded lines \(region.startLine + 1)-\(region.endLine + 1)" : "Unfolded lines \(region.startLine + 1)-\(region.endLine + 1)")
        }

        private func matchingBracketRanges() -> [NSRange] {
            guard lastAppearance.highlightsMatchingBrackets, let textView else {
                DebugFileLog.log("EditorDecorations", "matching brackets skipped enabled=\(lastAppearance.highlightsMatchingBrackets) textView=\(textView == nil ? "nil" : "set") filePath=\(state.filePath)")
                return []
            }
            let content = textView.string as NSString
            guard content.length > 0 else {
                DebugFileLog.log("EditorDecorations", "matching brackets skipped empty content filePath=\(state.filePath)")
                return []
            }
            let cursor = min(textView.selectedRange().location, content.length)
            let candidates = [cursor - 1, cursor].filter { $0 >= 0 && $0 < content.length }
            DebugFileLog.log("EditorDecorations", "matching bracket scan cursor=\(cursor) candidates=\(candidates) contentLength=\(content.length) filePath=\(state.filePath)")
            for location in candidates {
                guard let match = matchingBracketLocation(from: location, content: content) else { continue }
                DebugFileLog.log("EditorDecorations", "matching bracket found location=\(location) match=\(match) filePath=\(state.filePath)")
                return [NSRange(location: location, length: 1), NSRange(location: match, length: 1)]
            }
            DebugFileLog.log("EditorDecorations", "matching bracket none filePath=\(state.filePath)")
            return []
        }

        private func matchingBracketLocation(from location: Int, content: NSString) -> Int? {
            let character = content.character(at: location)
            let pairs = languagePairMap()
            let reversePairs = Dictionary(uniqueKeysWithValues: pairs.map { ($0.value, $0.key) })
            if let close = pairs[character] {
                return scanBracket(content: content, start: location + 1, open: character, close: close, direction: 1)
            }
            if let open = reversePairs[character] {
                return scanBracket(content: content, start: location - 1, open: open, close: character, direction: -1)
            }
            return nil
        }

        private func scanBracket(content: NSString, start: Int, open: unichar, close: unichar, direction: Int) -> Int? {
            var depth = 1
            var index = start
            while index >= 0, index < content.length {
                let character = content.character(at: index)
                if character == open {
                    depth += direction > 0 ? 1 : -1
                } else if character == close {
                    depth += direction > 0 ? -1 : 1
                }
                if depth == 0 { return index }
                index += direction
            }
            return nil
        }

        // MARK: - Viewport Mode Setup

        func enterViewportMode(scrollView: NSScrollView) {
            DebugFileLog.log("EditorViewport", "enterViewportMode requested filePath=\(state.filePath) store=\(state.backingStore == nil ? "nil" : "set") textView=\(textView == nil ? "nil" : "set")")
            guard let store = state.backingStore, let textView else { return }
            DebugFileLog.log("EditorViewport", "enterViewportMode start lineCount=\(store.lineCount) contentSize=\(scrollView.contentSize) filePath=\(state.filePath)")
            textView.allowsUndo = false
            textView.undoManager?.removeAllActions()
            textView.usesFindBar = false
            clearViewportHistory()

            let viewport = ViewportState(backingStore: store)
            viewport.updateEstimatedLineHeight(font: typography.nsFont(size: AppTypographySettings.defaultFontSize))
            viewportState = viewport
            invalidateRenderedViewportText()
            lastRenderedViewportRange = nil
            lastRenderedBackingStoreVersion = -1
            lastObservedClipSize = scrollView.contentView.bounds.size

            textView.isVerticallyResizable = false
            textView.autoresizingMask = []

            let container = ViewportContainerView()
            container.wantsLayer = true
            let height = max(viewport.totalDocumentHeight, scrollView.contentView.bounds.height)
            let width = max(scrollView.contentSize.width, textView.frame.width)
            container.frame = NSRect(x: 0, y: 0, width: width, height: height)
            container.autoresizingMask = []

            textView.removeFromSuperview()
            container.addSubview(textView)
            scrollView.documentView = container
            containerView = container
            refreshEditorDecorations()

            textView.frame = NSRect(
                x: 0, y: 0,
                width: width,
                height: viewport.estimatedLineHeight * CGFloat(min(Self.initialViewportLineLimit, viewport.visualLineCount))
            )
            DebugFileLog.log("EditorViewport", "enterViewportMode completed container=\(container.frame) textFrame=\(textView.frame) filePath=\(state.filePath)")
        }

        func updateContainerHeight() {
            guard let viewport = viewportState, let container = containerView, let scrollView else {
                DebugFileLog.log("EditorViewport", "updateContainerHeight skipped viewport=\(viewportState == nil ? "nil" : "set") container=\(containerView == nil ? "nil" : "set") scrollView=\(scrollView == nil ? "nil" : "set") filePath=\(state.filePath)")
                return
            }
            let height = max(viewport.totalDocumentHeight, scrollView.contentView.bounds.height)
            let width = max(scrollView.contentSize.width, textView?.frame.width ?? scrollView.contentSize.width)
            DebugFileLog.log("EditorViewport", "updateContainerHeight height=\(height) width=\(width) totalDocumentHeight=\(viewport.totalDocumentHeight) clip=\(scrollView.contentView.bounds) filePath=\(state.filePath)")
            container.frame = NSRect(x: 0, y: 0, width: width, height: height)
            updateMarkdownEditorScrollMetrics()
            let maxScrollY = max(0, height - scrollView.contentView.bounds.height)
            if scrollView.contentView.bounds.origin.y > maxScrollY {
                scrollView.contentView.setBoundsOrigin(NSPoint(x: scrollView.contentView.bounds.origin.x, y: maxScrollY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        func refreshViewport(force: Bool) {
            DebugFileLog.log("EditorViewport", "refreshViewport requested force=\(force) filePath=\(state.filePath)")
            guard let viewport = viewportState, let textView, let scrollView else {
                DebugFileLog.log("EditorViewport", "refreshViewport skipped viewport=\(viewportState == nil ? "nil" : "set") textView=\(textView == nil ? "nil" : "set") scrollView=\(scrollView == nil ? "nil" : "set") filePath=\(state.filePath)")
                return
            }
            let scrollY = scrollView.contentView.bounds.origin.y
            let visibleHeight = scrollView.contentView.bounds.height

            guard force || viewport.shouldUpdateViewport(scrollY: scrollY, visibleHeight: visibleHeight) else {
                DebugFileLog.log("EditorViewport", "refreshViewport no update scrollY=\(scrollY) visibleHeight=\(visibleHeight) viewport=\(viewport.viewportStartLine)..<\(viewport.viewportEndLine) filePath=\(state.filePath)")
                return
            }

            let previousRange = viewport.viewportStartLine ..< viewport.viewportEndLine

            let savedCursor = isScrollDrivenRefresh ? nil : globalCursorFromLocalLocation(textView.selectedRange().location)
            let savedSelectionLength = textView.selectedRange().length

            let newRange = viewport.computeViewport(scrollY: scrollY, visibleHeight: visibleHeight)
            if !force, newRange == previousRange {
                DebugFileLog.log("EditorViewport", "refreshViewport same range=\(newRange) filePath=\(state.filePath)")
                return
            }
            DebugFileLog.log("EditorViewport", "refreshViewport applying previous=\(previousRange) new=\(newRange) scrollY=\(scrollY) visibleHeight=\(visibleHeight) backingVersion=\(state.backingStoreVersion) filePath=\(state.filePath)")

            let perfStart = beginPerfTiming()
            let renderedLineCount = newRange.count
            defer {
                recordRefreshTiming(start: perfStart, durationLineCount: renderedLineCount, force: force)
            }

            viewport.applyViewport(newRange)

            let yOffset = viewport.viewportYOffset()
            let shouldReloadText = needsViewportTextReload
                || lastRenderedViewportRange != newRange
                || lastRenderedBackingStoreVersion != state.backingStoreVersion

            let text: String? = if shouldReloadText {
                viewport.viewportText()
            } else {
                nil
            }

            isUpdating = true
            CATransaction.begin()
            CATransaction.setDisableActions(true)

            if let text {
                DebugFileLog.log("EditorViewport", "refreshViewport reload text chars=\(text.count) filePath=\(state.filePath)")
                textView.string = text
                lastRenderedViewportRange = newRange
                lastRenderedBackingStoreVersion = state.backingStoreVersion
                needsViewportTextReload = false
                rebuildLineStartOffsetsForViewport()
            }
            let font = typography.nsFont(size: AppTypographySettings.defaultFontSize)
            if let storage = textView.textStorage, storage.length > 0 {
                let fullRange = NSRange(location: 0, length: storage.length)
                if shouldReloadText || force {
                    storage.beginEditing()
                    storage.addAttribute(.font, value: font, range: fullRange)
                    storage.addAttribute(
                        .paragraphStyle,
                        value: CodeEditorView.paragraphStyle(
                            tabInterval: CodeEditorView.tabInterval(for: lastAppearance.tabSize)
                        ),
                        range: fullRange
                    )
                    storage.endEditing()
                    DebugFileLog.log("EditorViewport", "refreshViewport applied attributes storageLength=\(storage.length) filePath=\(state.filePath)")
                    applySyntaxHighlights(storage: storage, viewport: viewport)
                } else {
                    refreshDiagnosticsIfNeeded()
                }
            }

            updateViewportFrames(
                viewport: viewport,
                textView: textView,
                scrollView: scrollView,
                yOffset: yOffset,
                visibleLineCount: newRange.count
            )

            CATransaction.commit()
            if isScrollDrivenRefresh, scrollView.contentView.bounds.origin.y != scrollY {
                scrollView.contentView.setBoundsOrigin(NSPoint(x: scrollView.contentView.bounds.origin.x, y: scrollY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            refreshEditorDecorations()
            DebugFileLog.log("EditorViewport", "refreshViewport committed textFrame=\(textView.frame) container=\(containerView?.frame.debugDescription ?? "nil") filePath=\(state.filePath)")

            if let savedCursor,
               let newLocalLine = viewport.viewportLine(forBackingStoreLine: savedCursor.line)
            {
                let newCharOffset = charOffsetForLocalLine(newLocalLine)
                let newContent = textView.string as NSString
                let lineRange = newContent.lineRange(for: NSRange(location: min(newCharOffset, newContent.length), length: 0))
                let lineLength = lineRange.length - (NSMaxRange(lineRange) < newContent.length ? 1 : 0)
                let newCursor = newCharOffset + min(savedCursor.column, max(0, lineLength))
                let safeCursor = min(newCursor, newContent.length)
                textView.setSelectedRange(NSRange(location: safeCursor, length: min(savedSelectionLength, newContent.length - safeCursor)))
            }

            isUpdating = false
            applyDiagnosticHighlights()
            applySearchHighlights()
            DebugFileLog.log("EditorViewport", "refreshViewport completed filePath=\(state.filePath)")
        }

        func applySyntaxHighlights(storage: NSTextStorage, viewport: ViewportState) {
            DebugFileLog.log("EditorSyntax", "applySyntaxHighlights requested storageLength=\(storage.length) viewport=\(viewport.viewportStartLine)..<\(viewport.viewportEndLine) filePath=\(state.filePath)")
            guard let highlighter = state.syntaxHighlighter,
                  let backingStore = state.backingStore,
                  let textView,
                  let layoutManager = textView.layoutManager
            else {
                DebugFileLog.log("EditorSyntax", "applySyntaxHighlights skipped highlighter=\(state.syntaxHighlighter == nil ? "nil" : "set") backingStore=\(state.backingStore == nil ? "nil" : "set") textView=\(textView == nil ? "nil" : "set") filePath=\(state.filePath)")
                return
            }
            let storageLength = storage.length
            guard storageLength > 0 else {
                DebugFileLog.log("EditorSyntax", "applySyntaxHighlights skipped empty storage filePath=\(state.filePath)")
                return
            }
            let range = viewport.viewportStartLine ..< viewport.viewportEndLine
            guard !range.isEmpty else {
                DebugFileLog.log("EditorSyntax", "applySyntaxHighlights skipped empty range filePath=\(state.filePath)")
                return
            }

            let spans = highlighter.spans(
                in: range,
                lineStartOffsets: lineStartOffsets,
                backingStore: backingStore
            )
            DebugFileLog.log("EditorSyntax", "applySyntaxHighlights spans=\(spans.count) storageLength=\(storageLength) lineOffsets=\(lineStartOffsets.count) filePath=\(state.filePath)")

            let fullRange = NSRange(location: 0, length: storageLength)
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
            for span in spans {
                let availableLength = storageLength - span.range.location
                guard span.range.location >= 0, availableLength > 0 else { continue }
                let clampedLength = min(span.range.length, availableLength)
                guard clampedLength > 0 else { continue }
                layoutManager.addTemporaryAttribute(
                    .foregroundColor,
                    value: SyntaxTheme.color(for: span.scope),
                    forCharacterRange: NSRange(location: span.range.location, length: clampedLength)
                )
            }
            refreshDiagnosticsIfNeeded(force: true)
            DebugFileLog.log("EditorSyntax", "applySyntaxHighlights completed spans=\(spans.count) filePath=\(state.filePath)")
        }

        func refreshDiagnosticsIfNeeded(force: Bool = false) {
            guard let viewport = viewportState else { return }
            let diagnostics = DiagnosticsStore.shared.diagnostics(for: state.filePath)
            let fingerprint = diagnostics.map { "\($0.id)|\($0.line)|\($0.column)|\($0.severity.rawValue)" }.joined(separator: "\n")
            let viewportRange = viewport.viewportStartLine ..< viewport.viewportEndLine
            guard force || fingerprint != lastDiagnosticFingerprint || viewportRange != lastDiagnosticViewportRange else { return }
            lastDiagnosticFingerprint = fingerprint
            lastDiagnosticViewportRange = viewportRange
            applyDiagnosticHighlights(diagnostics: diagnostics)
        }

        func applyDiagnosticHighlights(diagnostics: [EditorDiagnostic]? = nil) {
            guard let textView, let layoutManager = textView.layoutManager, let viewport = viewportState else { return }
            let storageLength = textView.textStorage?.length ?? 0
            clearAppliedDiagnosticHighlights(layoutManager: layoutManager, storageLength: storageLength)
            guard storageLength > 0 else { return }
            let diagnostics = diagnostics ?? DiagnosticsStore.shared.diagnostics(for: state.filePath)
            var nextRanges: [NSRange] = []
            for diagnostic in diagnostics {
                let globalLine = diagnostic.line - 1
                guard let localLine = viewport.viewportLine(forBackingStoreLine: globalLine) else { continue }
                let localCharOffset = charOffsetForLocalLine(localLine)
                let lineRange = (textView.string as NSString).lineRange(for: NSRange(location: min(localCharOffset, storageLength), length: 0))
                let lineLength = max(0, lineRange.length - (NSMaxRange(lineRange) < storageLength ? 1 : 0))
                let columnOffset = min(max(0, diagnostic.column - 1), lineLength)
                let length = max(1, min(max(1, lineLength - columnOffset), 24))
                let range = NSRange(location: localCharOffset + columnOffset, length: length)
                guard NSMaxRange(range) <= storageLength else { continue }
                nextRanges.append(range)
                layoutManager.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: range)
                layoutManager.addTemporaryAttribute(.underlineColor, value: diagnosticColor(diagnostic.severity), forCharacterRange: range)
            }
            appliedDiagnosticRanges = nextRanges
            textView.needsDisplay = true
            containerView?.diagnostics = diagnostics
            containerView?.needsDisplay = true
        }

        private var appliedDiagnosticRanges: [NSRange] = []

        private func clearAppliedDiagnosticHighlights(layoutManager: NSLayoutManager, storageLength: Int) {
            for range in appliedDiagnosticRanges where NSMaxRange(range) <= storageLength {
                layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: range)
                layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: range)
            }
            appliedDiagnosticRanges.removeAll(keepingCapacity: true)
        }

        private func diagnosticColor(_ severity: EditorDiagnosticSeverity) -> NSColor {
            switch severity {
            case .error: NSColor.systemRed
            case .warning: NSColor.systemYellow
            case .information: NSColor.systemBlue
            case .hint: GhosttyService.shared.foregroundColor.withAlphaComponent(0.55)
            }
        }

        func invalidateSyntaxHighlightsFromLine(_ line: Int) {
            DebugFileLog.log("EditorSyntax", "invalidate from line=\(line) filePath=\(state.filePath)")
            state.syntaxHighlighter?.invalidate(fromLine: max(0, line))
        }

        func reapplySyntaxHighlights() {
            DebugFileLog.log("EditorSyntax", "reapply requested filePath=\(state.filePath)")
            guard let textView, let storage = textView.textStorage, let viewport = viewportState else {
                DebugFileLog.log("EditorSyntax", "reapply skipped textView=\(textView == nil ? "nil" : "set") viewport=\(viewportState == nil ? "nil" : "set") filePath=\(state.filePath)")
                return
            }
            applySyntaxHighlights(storage: storage, viewport: viewport)
        }

        func applyIncrementalSyntaxHighlights(
            startLine: Int,
            oldLineCount: Int,
            newLineCount: Int
        ) {
            DebugFileLog.log("EditorSyntax", "incremental requested startLine=\(startLine) old=\(oldLineCount) new=\(newLineCount) filePath=\(state.filePath)")
            guard let highlighter = state.syntaxHighlighter,
                  let backingStore = state.backingStore,
                  let viewport = viewportState,
                  let textView,
                  let storage = textView.textStorage
            else {
                DebugFileLog.log("EditorSyntax", "incremental skipped highlighter=\(state.syntaxHighlighter == nil ? "nil" : "set") backingStore=\(state.backingStore == nil ? "nil" : "set") viewport=\(viewportState == nil ? "nil" : "set") textView=\(textView == nil ? "nil" : "set") filePath=\(state.filePath)")
                return
            }

            let outcome = highlighter.applyEdit(
                startLine: startLine,
                oldLineCount: oldLineCount,
                newLineCount: newLineCount,
                backingStore: backingStore
            )

            applySyntaxAttributes(
                storage: storage,
                viewport: viewport,
                highlighter: highlighter,
                lineRange: startLine ..< startLine + newLineCount
            )

            if case .cascade = outcome {
                DebugFileLog.log("EditorSyntax", "incremental cascade scheduled filePath=\(state.filePath)")
                scheduleCascadeReapply()
            }
            refreshDiagnosticsIfNeeded()
            DebugFileLog.log("EditorSyntax", "incremental completed filePath=\(state.filePath)")
        }

        private func scheduleCascadeReapply() {
            pendingCascadeReapplyGeneration &+= 1
            let generation = pendingCascadeReapplyGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16)) { [weak self] in
                guard let self, self.pendingCascadeReapplyGeneration == generation else { return }
                self.reapplySyntaxHighlights()
            }
        }

        private func applySyntaxAttributes(
            storage: NSTextStorage,
            viewport: ViewportState,
            highlighter: any SyntaxHighlighting,
            lineRange: Range<Int>
        ) {
            guard let textView, let layoutManager = textView.layoutManager else { return }
            let storageLength = storage.length
            guard storageLength > 0 else { return }

            let viewportStart = viewport.viewportStartLine
            let localStart = max(0, lineRange.lowerBound - viewportStart)
            let localEndRaw = lineRange.upperBound - viewportStart
            let localEnd = min(localEndRaw, viewport.viewportLineCount)
            guard localStart < localEnd, localStart < lineStartOffsets.count else { return }

            let charStart = lineStartOffsets[localStart]
            let charEnd: Int = localEnd < lineStartOffsets.count ? lineStartOffsets[localEnd] : storageLength
            guard charEnd > charStart, charStart >= 0, charEnd <= storageLength else { return }

            layoutManager.removeTemporaryAttribute(
                .foregroundColor,
                forCharacterRange: NSRange(location: charStart, length: charEnd - charStart)
            )
            for localIndex in localStart ..< localEnd {
                let globalLine = viewportStart + localIndex
                guard let tokens = highlighter.tokens(forLine: globalLine) else { continue }
                let lineOffset = lineStartOffsets[localIndex]
                for token in tokens {
                    let location = lineOffset + token.location
                    guard location >= 0, location + token.length <= storageLength else { continue }
                    layoutManager.addTemporaryAttribute(
                        .foregroundColor,
                        value: SyntaxTheme.color(for: token.scope),
                        forCharacterRange: NSRange(location: location, length: token.length)
                    )
                }
            }
        }

        func rebuildLineStartOffsetsForViewport() {
            guard let textView else {
                DebugFileLog.log("EditorViewport", "rebuildLineStartOffsets skipped missing textView filePath=\(state.filePath)")
                return
            }
            let content = textView.string as NSString
            var offsets = [0]
            offsets.reserveCapacity(content.length / 40)
            var searchRange = NSRange(location: 0, length: content.length)
            while searchRange.location < content.length {
                let found = content.range(of: "\n", options: [], range: searchRange)
                guard found.location != NSNotFound else { break }
                let next = found.location + found.length
                if next <= content.length {
                    offsets.append(next)
                }
                searchRange.location = next
                searchRange.length = content.length - next
            }
            lineStartOffsets = offsets
            DebugFileLog.log("EditorViewport", "rebuilt line offsets count=\(offsets.count) contentLength=\(content.length) filePath=\(state.filePath)")
        }

        private func updateLineStartOffsetsAfterEdit(
            viewportStartLine: Int,
            globalStartLine: Int,
            oldLineCount: Int,
            newLines: [String]
        ) {
            let localStart = globalStartLine - viewportStartLine
            let oldCount = lineStartOffsets.count
            guard localStart >= 0,
                  localStart < oldCount,
                  localStart + oldLineCount <= oldCount,
                  localStart + oldLineCount < oldCount
            else {
                rebuildLineStartOffsetsForViewport()
                return
            }

            let baseOffset = lineStartOffsets[localStart]
            let oldBlockSpan = lineStartOffsets[localStart + oldLineCount] - baseOffset

            var newBlockSpan = 0
            var newOffsets: [Int] = []
            newOffsets.reserveCapacity(newLines.count)
            for line in newLines {
                newOffsets.append(baseOffset + newBlockSpan)
                newBlockSpan += (line as NSString).length + 1
            }

            let delta = newBlockSpan - oldBlockSpan
            lineStartOffsets.replaceSubrange(localStart ..< localStart + oldLineCount, with: newOffsets)

            let shiftStart = localStart + newLines.count
            if delta != 0, shiftStart < lineStartOffsets.count {
                for index in shiftStart ..< lineStartOffsets.count {
                    lineStartOffsets[index] += delta
                }
            }
        }

        // MARK: - Editor Focus

        func focusEditorPreservingSelection() {
            guard let textView else { return }
            if let viewport = viewportState, !viewportSearchMatches.isEmpty {
                let currentIndex = max(0, state.searchCurrentIndex - 1)
                if currentIndex < viewportSearchMatches.count {
                    let match = viewportSearchMatches[currentIndex]
                    if let localLine = viewport.viewportLine(forBackingStoreLine: match.lineIndex) {
                        let localCharOffset = charOffsetForLocalLine(localLine)
                        let selectRange = NSRange(
                            location: localCharOffset + match.range.location,
                            length: match.range.length
                        )
                        let content = textView.string as NSString
                        if NSMaxRange(selectRange) <= content.length {
                            textView.setSelectedRange(selectRange)
                        }
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak textView] in
                guard let textView, let window = textView.window else { return }
                window.makeFirstResponder(textView)
            }
        }

        func navigateToRequestedSymbol() {
            guard let symbol = state.symbolNavigationRequest else { return }
            scrollToGlobalLine(symbol.line, column: symbol.column)
            textView?.window?.makeFirstResponder(textView)
        }

        func navigateToRequestedLine() {
            guard let request = state.lineNavigationRequest else { return }
            let maxLine = max(0, (viewportState?.backingStore.lineCount ?? state.backingStore?.lineCount ?? 1) - 1)
            let targetLine = min(max(0, request.line - 1), maxLine)
            scrollToGlobalLine(targetLine, column: max(0, request.column - 1))
            textView?.window?.makeFirstResponder(textView)
        }

        func prepareInlineEdit() {
            guard let textView else { return }
            let range = textView.selectedRange()
            let content = textView.string as NSString
            guard range.location != NSNotFound, range.length > 0, NSMaxRange(range) <= content.length else {
                ToastState.shared.show("Select code before using Inline Edit")
                state.inlineEditVisible = false
                return
            }
            state.proposeInlineEdit(instruction: "", original: content.substring(with: range))
        }

        func applyInlineEditProposal() {
            guard let textView else { return }
            let range = textView.selectedRange()
            guard range.location != NSNotFound, range.length > 0 else { return }
            textView.insertText(state.inlineEditProposal, replacementRange: range)
        }

        // MARK: - Search Highlighting

        func clearSearchHighlights() {
            viewportSearchMatches = []
            state.searchMatchCount = 0
            state.searchCurrentIndex = 0
            applySearchHighlights()
        }

        func applySearchHighlights(force: Bool = false) {
            let perfStart = beginPerfTiming()
            var highlightedRangeCount = 0
            defer {
                recordHighlightTiming(start: perfStart, highlightedRangeCount: highlightedRangeCount, force: force)
            }

            guard let textView, let layoutManager = textView.layoutManager else { return }
            let storageLength = textView.textStorage?.length ?? 0
            guard storageLength > 0 else {
                appliedSearchHighlightRanges.removeAll(keepingCapacity: true)
                appliedCurrentSearchMatchRange = nil
                return
            }

            guard let viewport = viewportState, !viewportSearchMatches.isEmpty else {
                guard !appliedSearchHighlightRanges.isEmpty || appliedCurrentSearchMatchRange != nil else { return }
                clearAppliedSearchHighlights(layoutManager: layoutManager, storageLength: storageLength)
                textView.needsDisplay = true
                return
            }

            var nextRanges: [NSRange] = []
            nextRanges.reserveCapacity(min(viewportSearchMatches.count, 256))

            let currentIndex = max(0, state.searchCurrentIndex - 1)
            var nextCurrentRange: NSRange?
            let visibleStartLine = viewport.viewportStartLine
            let visibleEndLine = viewport.viewportEndLine

            for (i, match) in viewportSearchMatches.enumerated() {
                if match.lineIndex < visibleStartLine {
                    continue
                }
                if match.lineIndex >= visibleEndLine {
                    break
                }
                guard let localLine = viewport.viewportLine(forBackingStoreLine: match.lineIndex) else { continue }
                let localCharOffset = charOffsetForLocalLine(localLine)
                let highlightRange = NSRange(
                    location: localCharOffset + match.range.location,
                    length: match.range.length
                )
                guard NSMaxRange(highlightRange) <= storageLength else { continue }
                nextRanges.append(highlightRange)
                if i == currentIndex {
                    nextCurrentRange = highlightRange
                }
            }

            if !force,
               appliedSearchHighlightRanges == nextRanges,
               appliedCurrentSearchMatchRange == nextCurrentRange
            {
                return
            }

            clearAppliedSearchHighlights(layoutManager: layoutManager, storageLength: storageLength)
            guard !nextRanges.isEmpty else {
                textView.needsDisplay = true
                return
            }

            let matchBg = GhosttyService.shared.foregroundColor.withAlphaComponent(0.2)
            let themeYellow = GhosttyService.shared.paletteColor(at: 3) ?? NSColor.systemYellow
            let currentMatchBg = themeYellow.withAlphaComponent(0.85)
            let currentMatchFg = GhosttyService.shared.backgroundColor

            for highlightRange in nextRanges {
                if highlightRange == nextCurrentRange {
                    layoutManager.addTemporaryAttribute(.backgroundColor, value: currentMatchBg, forCharacterRange: highlightRange)
                    layoutManager.addTemporaryAttribute(.foregroundColor, value: currentMatchFg, forCharacterRange: highlightRange)
                } else {
                    layoutManager.addTemporaryAttribute(.backgroundColor, value: matchBg, forCharacterRange: highlightRange)
                }
            }

            highlightedRangeCount = nextRanges.count
            appliedSearchHighlightRanges = nextRanges
            appliedCurrentSearchMatchRange = nextCurrentRange
            textView.needsDisplay = true
        }

        // MARK: - Viewport Search

        private var viewportSearchMatches: [TextBackingStore.SearchMatch] = []
        private var appliedSearchHighlightRanges: [NSRange] = []
        private var appliedCurrentSearchMatchRange: NSRange?

        private func clearAppliedSearchHighlights(layoutManager: NSLayoutManager, storageLength: Int) {
            for range in appliedSearchHighlightRanges {
                guard NSMaxRange(range) <= storageLength else { continue }
                layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
                layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
            }
            if let range = appliedCurrentSearchMatchRange, NSMaxRange(range) <= storageLength {
                layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
            }
            appliedSearchHighlightRanges.removeAll(keepingCapacity: true)
            appliedCurrentSearchMatchRange = nil
        }

        func performSearchViewport(_ needle: String, caseSensitive: Bool, useRegex: Bool) {
            guard let store = state.backingStore else { return }
            state.searchInvalidRegex = false
            viewportSearchMatches = []
            guard !needle.isEmpty else {
                state.searchMatchCount = 0
                state.searchCurrentIndex = 0
                applySearchHighlights()
                return
            }
            if useRegex {
                if (try? NSRegularExpression(pattern: needle)) == nil {
                    state.searchInvalidRegex = true
                    state.searchMatchCount = 0
                    state.searchCurrentIndex = 0
                    applySearchHighlights()
                    return
                }
            }
            viewportSearchMatches = store.search(needle: needle, caseSensitive: caseSensitive, useRegex: useRegex)
            state.searchMatchCount = viewportSearchMatches.count
            if !viewportSearchMatches.isEmpty {
                state.searchCurrentIndex = 1
                scrollToSearchMatch(at: 0)
            } else {
                state.searchCurrentIndex = 0
                applySearchHighlights()
            }
        }

        func navigateSearchViewport(forward: Bool) {
            guard !viewportSearchMatches.isEmpty else { return }
            var idx = state.searchCurrentIndex - 1
            if forward {
                idx = (idx + 1) % viewportSearchMatches.count
            } else {
                idx = (idx - 1 + viewportSearchMatches.count) % viewportSearchMatches.count
            }
            state.searchCurrentIndex = idx + 1
            scrollToSearchMatch(at: idx)
        }

        func replaceCurrentViewport(with replacement: String, needle: String, caseSensitive: Bool, useRegex: Bool) {
            guard let store = state.backingStore, !needle.isEmpty, !viewportSearchMatches.isEmpty else { return }
            clearViewportHistory()
            let currentIndex = max(0, state.searchCurrentIndex - 1)
            guard currentIndex < viewportSearchMatches.count else { return }
            let match = viewportSearchMatches[currentIndex]
            let nextMatch = store.replaceFirstMatch(
                match,
                with: replacement,
                needle: needle,
                caseSensitive: caseSensitive,
                useRegex: useRegex
            )
            state.backingStoreVersion += 1
            lastSyncedBackingStoreVersion = state.backingStoreVersion
            state.markModified()
            state.notifyLanguageServerChanged()
            scheduleLSPChange()
            invalidateSyntaxHighlightsFromLine(match.lineIndex)
            invalidateRenderedViewportText()
            scheduleMarkdownPreviewRefresh(immediate: true)
            performSearchViewport(needle, caseSensitive: caseSensitive, useRegex: useRegex)
            if let nextMatch,
               let nextIndex = viewportSearchMatches.firstIndex(where: { $0.lineIndex == nextMatch.lineIndex && $0.range == nextMatch.range })
            {
                state.searchCurrentIndex = nextIndex + 1
                scrollToSearchMatch(at: nextIndex)
            }
            refreshViewport(force: true)
        }

        func replaceAllViewport(with replacement: String, needle: String, caseSensitive: Bool, useRegex: Bool) {
            guard let store = state.backingStore, !needle.isEmpty, !viewportSearchMatches.isEmpty else { return }
            clearViewportHistory()
            let earliestInvalidation = store.replaceAllMatches(viewportSearchMatches, with: replacement)
            if let earliestInvalidation {
                invalidateSyntaxHighlightsFromLine(earliestInvalidation)
            }
            state.backingStoreVersion += 1
            lastSyncedBackingStoreVersion = state.backingStoreVersion
            state.markModified()
            state.notifyLanguageServerChanged()
            invalidateRenderedViewportText()
            scheduleMarkdownPreviewRefresh(immediate: true)
            performSearchViewport(needle, caseSensitive: caseSensitive, useRegex: useRegex)
            viewportState?.rebuildVisualLines(collapsedRegions: state.foldRegions().filter { state.isFoldRegionCollapsed($0) })
            updateContainerHeight()
            refreshViewport(force: true)
        }

        private func scrollToSearchMatch(at index: Int) {
            guard index >= 0, index < viewportSearchMatches.count,
                  let viewport = viewportState, let scrollView, let textView
            else { return }
            let match = viewportSearchMatches[index]
            if state.unfoldRegions(containing: match.lineIndex) {
                viewport.rebuildVisualLines(collapsedRegions: state.foldRegions().filter { state.isFoldRegionCollapsed($0) })
                invalidateRenderedViewportText()
                updateContainerHeight()
            }
            let targetScrollY = viewport.scrollY(forLine: match.lineIndex)
            let visibleHeight = scrollView.contentView.bounds.height
            let centeredY = max(0, targetScrollY - visibleHeight / 2)
            scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: centeredY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            refreshViewport(force: true)

            guard let localLine = viewport.viewportLine(forBackingStoreLine: match.lineIndex) else { return }
            let localCharOffset = charOffsetForLocalLine(localLine)
            let matchStart = localCharOffset + match.range.location
            let content = textView.string as NSString
            guard matchStart <= content.length else { return }
            textView.setSelectedRange(NSRange(location: matchStart, length: 0))
            applySearchHighlights()
        }

        private func charOffsetForLocalLine(_ localLine: Int) -> Int {
            guard localLine >= 0, localLine < lineStartOffsets.count else { return 0 }
            return lineStartOffsets[localLine]
        }

        private func viewportContentWidth(for textView: NSTextView, scrollView: NSScrollView) -> CGFloat {
            guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
                return scrollView.contentSize.width
            }
            layoutManager.ensureLayout(for: textContainer)
            let padding = textView.textContainerInset.width * 2 + textContainer.lineFragmentPadding * 2
            let usedWidth = layoutManager.usedRect(for: textContainer).width + padding
            return max(scrollView.contentSize.width, ceil(usedWidth))
        }

        private func updateViewportFrames(
            viewport: ViewportState,
            textView: NSTextView,
            scrollView: NSScrollView,
            yOffset: CGFloat,
            visibleLineCount: Int
        ) {
            let estimatedHeight = viewport.estimatedLineHeight * CGFloat(max(1, visibleLineCount))
                + textView.textContainerInset.height * 2
            let viewportWidth = viewportContentWidth(for: textView, scrollView: scrollView)
            if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
                layoutManager.ensureLayout(for: textContainer)
            }
            let laidOutHeight: CGFloat = if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
                ceil(layoutManager.usedRect(for: textContainer).height + textView.textContainerInset.height * 2)
            } else {
                estimatedHeight
            }
            let newTextFrame = NSRect(
                x: 0,
                y: yOffset,
                width: viewportWidth,
                height: max(estimatedHeight, laidOutHeight, 100)
            )
            if textView.frame != newTextFrame {
                textView.frame = newTextFrame
            }

            if let container = containerView {
                let containerHeight = max(viewport.totalDocumentHeight, scrollView.contentView.bounds.height)
                let newContainerFrame = NSRect(
                    x: 0,
                    y: 0,
                    width: viewportWidth,
                    height: containerHeight
                )
                if container.frame != newContainerFrame {
                    container.frame = newContainerFrame
                }
            }
        }

        private func ensureViewportMinimumWidth() {
            guard let viewport = viewportState, let scrollView, let textView, let container = containerView else { return }
            let minimumWidth = scrollView.contentSize.width
            guard textView.frame.width < minimumWidth || container.frame.width < minimumWidth else { return }
            let width = max(minimumWidth, textView.frame.width)
            textView.frame = NSRect(
                x: textView.frame.origin.x,
                y: textView.frame.origin.y,
                width: width,
                height: textView.frame.height
            )
            container.frame = NSRect(
                x: 0,
                y: 0,
                width: width,
                height: max(viewport.totalDocumentHeight, scrollView.contentView.bounds.height)
            )
        }

        // MARK: - Scroll Observer

        func setScrollObserver(for scrollView: NSScrollView) {
            guard observedContentView !== scrollView.contentView else { return }
            removeScrollObserver()
            observedContentView = scrollView.contentView
            lastObservedClipSize = scrollView.contentView.bounds.size
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleScrollBoundsChange),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleClipFrameChange),
                name: NSView.frameDidChangeNotification,
                object: scrollView.contentView
            )
            updateMarkdownEditorScrollMetrics()
            updateMarkdownPreviewSyncPointFromEditorScroll()
        }

        private func removeScrollObserver() {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: observedContentView
            )
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.frameDidChangeNotification,
                object: observedContentView
            )
            observedContentView = nil
            lastObservedClipSize = .zero
        }

        @objc
        private func handleScrollBoundsChange() {
            reconcileScrollBoundsChange(observedContentView?.bounds.size)
        }

        @objc
        private func handleClipFrameChange() {
            reconcileClipFrameChange(observedContentView?.frame.size)
        }

        private func reconcileScrollBoundsChange(_ size: CGSize?) {
            if let size {
                if size.width != lastObservedClipSize.width {
                    ensureViewportMinimumWidth()
                }
                if size.height != lastObservedClipSize.height {
                    updateContainerHeight()
                }
                lastObservedClipSize = size
            }
            updateMarkdownEditorScrollMetrics()
            if !isMarkdownSplitActive {
                isApplyingMarkdownScroll = false
            } else if isApplyingMarkdownScroll {
                isApplyingMarkdownScroll = false
            } else {
                if state.markdownScrollDriver != .editor {
                    state.markdownScrollDriver = .editor
                }
                updateMarkdownPreviewSyncPointFromEditorScroll()
            }
            if !isEditingViewport {
                scheduleViewportRefresh()
            }
        }

        private func reconcileClipFrameChange(_ size: CGSize?) {
            if let size {
                if size.width != lastObservedClipSize.width {
                    ensureViewportMinimumWidth()
                }
                if size.height != lastObservedClipSize.height {
                    updateContainerHeight()
                }
                lastObservedClipSize = size
            }
            updateMarkdownEditorScrollMetrics()
            if !isEditingViewport {
                scheduleViewportRefresh()
            }
        }

        private func scheduleViewportRefresh() {
            pendingScrollRefreshTask?.cancel()
            let targetScrollY = scrollView?.contentView.bounds.origin.y
            pendingScrollRefreshTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self, !self.isEditingViewport else { return }
                if let targetScrollY, let scrollView = self.scrollView, abs(scrollView.contentView.bounds.origin.y - targetScrollY) > 0.5 {
                    self.scheduleViewportRefresh()
                    return
                }
                self.isScrollDrivenRefresh = true
                defer { self.isScrollDrivenRefresh = false }
                self.refreshViewport(force: false)
            }
        }

        private var isMarkdownSplitActive: Bool {
            state.isMarkdownFile && state.markdownViewMode == .split && state.markdownScrollSyncEnabled
        }

        func updateMarkdownEditorScrollMetrics() {
            guard isMarkdownSplitActive,
                  let scrollView,
                  let viewport = viewportState
            else { return }

            let visibleHeight = scrollView.contentView.bounds.height
            let documentHeight = scrollView.documentView?.bounds.height ?? 0
            let maxScrollY = max(0, documentHeight - visibleHeight)
            let scrollY = min(max(0, scrollView.contentView.bounds.origin.y), maxScrollY)

            state.markdownEditorScrollY = scrollY
            state.markdownEditorMaxScrollY = maxScrollY
            state.markdownEditorViewportHeight = visibleHeight
            state.markdownEditorLineHeight = viewport.estimatedLineHeight
        }

        func syncMarkdownScrollPositionIfNeeded() {
            guard state.isMarkdownFile,
                  state.markdownViewMode == .split,
                  state.markdownScrollSyncEnabled
            else { return }

            applyPendingMarkdownEditorScrollRequestIfNeeded()
        }

        func updateMarkdownPreviewSyncPointFromEditorScroll() {
            guard !isApplyingMarkdownScroll else { return }
            guard state.markdownScrollDriver != .preview else { return }
            guard state.isMarkdownFile,
                  state.markdownViewMode == .split,
                  state.markdownScrollSyncEnabled
            else { return }

            let map = state.currentMarkdownSyncMap()
            let output = state.markdownSyncCoordinator.editorDidScroll(scrollY: state.markdownEditorScrollY, map: map)
            guard !output.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.state.applyMarkdownSyncOutput(output)
            }
        }

        private var lastAppliedMarkdownEditorScrollRequestVersion: Int {
            get { _lastAppliedMarkdownEditorScrollRequestVersion }
            set { _lastAppliedMarkdownEditorScrollRequestVersion = newValue }
        }

        private var _lastAppliedMarkdownEditorScrollRequestVersion: Int = 0

        private func applyPendingMarkdownEditorScrollRequestIfNeeded() {
            guard let scrollView, viewportState != nil else { return }
            guard lastAppliedMarkdownEditorScrollRequestVersion != state.markdownEditorScrollRequestVersion else { return }
            lastAppliedMarkdownEditorScrollRequestVersion = state.markdownEditorScrollRequestVersion

            guard state.isMarkdownFile,
                  state.markdownViewMode == .split,
                  state.markdownScrollSyncEnabled,
                  let targetY = state.markdownEditorScrollRequestY
            else { return }

            isApplyingMarkdownScroll = true
            let visibleHeight = scrollView.contentView.bounds.height
            let documentHeight = scrollView.documentView?.bounds.height ?? 0
            let maxScrollY = max(0, documentHeight - visibleHeight)
            let clamped = min(max(0, targetY), maxScrollY)
            scrollView.contentView.setBoundsOrigin(NSPoint(x: scrollView.contentView.bounds.origin.x, y: clamped))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            refreshViewport(force: true)
            rebuildLineStartOffsetsForViewport()
        }

        private func publishMarkdownProgressIfEditorAutoScrolled(_ work: () -> Void) {
            guard let scrollView else {
                work()
                return
            }

            let beforeY = scrollView.contentView.bounds.origin.y
            work()
            let afterY = scrollView.contentView.bounds.origin.y

            guard abs(afterY - beforeY) > 0.5 else { return }
            updateMarkdownEditorScrollMetrics()
            updateMarkdownPreviewSyncPointFromEditorScroll()
        }

        private func markdownScrollProgress(for scrollView: NSScrollView) -> CGFloat {
            let visibleHeight = scrollView.contentView.bounds.height
            let documentHeight = scrollView.documentView?.bounds.height ?? 0
            let maxScrollY = max(0, documentHeight - visibleHeight)
            let scrollY = min(max(0, scrollView.contentView.bounds.origin.y), maxScrollY)
            return maxScrollY > 0 ? scrollY / maxScrollY : 0
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_: Notification) {
            guard let textView, !isUpdating else { return }
            handleTextDidChangeViewport(textView)
            scheduleMarkdownPreviewRefresh()
        }

        private func scheduleMarkdownPreviewRefresh(immediate: Bool = false) {
            guard state.isMarkdownFile else { return }
            previewRefreshTask?.cancel()
            if immediate {
                state.previewRefreshVersion += 1
                return
            }
            let task = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: Self.previewRefreshDebounceNanos)
                guard !Task.isCancelled, let self else { return }
                guard self.previewRefreshTask?.isCancelled == false else { return }
                self.state.previewRefreshVersion += 1
            }
            previewRefreshTask = task
        }

        func scheduleLSPChange() {
            lspChangeTask?.cancel()
            let version = state.lspChangeVersion
            lspChangeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: Self.lspChangeDebounceNanos)
                guard !Task.isCancelled, let self else { return }
                guard self.state.lspChangeVersion == version else { return }
                guard let text = self.state.backingStore?.fullText() else { return }
                LanguageServerManager.shared.didChange(
                    filePath: self.state.filePath,
                    projectPath: self.state.projectPath,
                    text: text
                )
            }
        }

        private func handleTextDidChangeViewport(_ textView: NSTextView) {
            guard let viewport = viewportState, let scrollView else { return }
            let pendingEdit = pendingViewportEdit
            pendingViewportEdit = nil
            let cursorLocation = textView.selectedRange().location
            let viewportStartLine = viewport.viewportStartLine
            var lineDelta = 0
            var recordedViewportEdit = false

            if let pendingEdit {
                applyPendingEdit(pendingEdit, to: viewport.backingStore)
                lineDelta = pendingEdit.newLines.count - pendingEdit.oldLines.count
                let newViewportEnd = max(viewportStartLine, viewport.viewportEndLine + lineDelta)
                viewport.applyViewport(viewportStartLine ..< newViewportEnd)
            } else {
                if !isApplyingViewportHistory {
                    clearViewportHistory()
                }
                let newLocalText = textView.string
                let newLocalLines = newLocalText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                let oldRange = viewport.viewportStartLine ..< viewport.viewportEndLine
                _ = viewport.backingStore.replaceLines(in: oldRange, with: newLocalLines)
                lineDelta = newLocalLines.count - oldRange.count
                viewport.applyViewport(viewport.viewportStartLine ..< viewport.viewportStartLine + newLocalLines.count)
                invalidateSyntaxHighlightsFromLine(viewportStartLine)
            }

            state.backingStoreVersion += 1
            lastSyncedBackingStoreVersion = state.backingStoreVersion
            state.markModified()
            state.notifyLanguageServerChanged()

            isEditingViewport = true
            defer { isEditingViewport = false }

            lastRenderedViewportRange = viewport.viewportStartLine ..< viewport.viewportEndLine
            lastRenderedBackingStoreVersion = state.backingStoreVersion
            needsViewportTextReload = false
            rebuildLineStartOffsetsForViewport()

            if let pendingEdit,
               !isApplyingViewportHistory,
               let selectionAfter = globalCursorFromLocalLocation(cursorLocation)
            {
                pushViewportEdit(ViewportEdit(
                    startLine: pendingEdit.startLine,
                    oldLines: pendingEdit.oldLines,
                    newLines: pendingEdit.newLines,
                    selectionBefore: pendingEdit.selectionBefore,
                    selectionAfter: selectionAfter
                ))
                recordedViewportEdit = true
            }

            if pendingEdit != nil, !recordedViewportEdit, !isApplyingViewportHistory {
                clearViewportHistory()
            }

            if lineDelta != 0 {
                viewport.rebuildVisualLines(collapsedRegions: state.foldRegions().filter { state.isFoldRegionCollapsed($0) })
                updateContainerHeight()
                updateViewportFrames(
                    viewport: viewport,
                    textView: textView,
                    scrollView: scrollView,
                    yOffset: viewport.viewportYOffset(),
                    visibleLineCount: max(1, viewport.viewportLineCount)
                )
            }

            publishMarkdownProgressIfEditorAutoScrolled {
                scrollCursorVisibleInViewport(textView: textView, cursorLocation: cursorLocation)
            }

            let scrollY = scrollView.contentView.bounds.origin.y
            let visibleHeight = scrollView.contentView.bounds.height
            if viewport.shouldUpdateViewport(scrollY: scrollY, visibleHeight: visibleHeight) {
                if let pendingEdit {
                    invalidateSyntaxHighlightsFromLine(pendingEdit.startLine)
                }
                let localLine = lineNumber(atCharacterLocation: cursorLocation)
                let globalLine = viewport.backingStoreLine(forViewportLine: localLine - 1)
                let columnOffset = cursorLocation - lineStartOffsets[max(0, min(localLine - 1, lineStartOffsets.count - 1))]

                refreshViewport(force: true)

                if let newLocalLine = viewport.viewportLine(forBackingStoreLine: globalLine) {
                    let newCharOffset = charOffsetForLocalLine(newLocalLine)
                    let content = textView.string as NSString
                    let lineRange = content.lineRange(for: NSRange(location: newCharOffset, length: 0))
                    let lineLength = lineRange.length - (NSMaxRange(lineRange) < content.length ? 1 : 0)
                    let newCursor = newCharOffset + min(columnOffset, max(0, lineLength))
                    let safeCursor = min(newCursor, content.length)
                    textView.setSelectedRange(NSRange(location: safeCursor, length: 0))
                    publishMarkdownProgressIfEditorAutoScrolled {
                        scrollCursorVisibleInViewport(textView: textView, cursorLocation: safeCursor)
                    }
                }
            } else {
                if let pendingEdit {
                    applyIncrementalSyntaxHighlights(
                        startLine: pendingEdit.startLine,
                        oldLineCount: pendingEdit.oldLines.count,
                        newLineCount: pendingEdit.newLines.count
                    )
                } else {
                    applyIncrementalSyntaxHighlights(
                        startLine: max(0, lineNumber(atCharacterLocation: cursorLocation) - 1),
                        oldLineCount: 1,
                        newLineCount: 1
                    )
                }
            }
        }

        func clearViewportHistory() {
            pendingViewportEdit = nil
            viewportUndoStack.removeAll(keepingCapacity: false)
            viewportRedoStack.removeAll(keepingCapacity: false)
            lastViewportEditTimestamp = nil
        }

        func performUndoRequest() -> Bool {
            if viewportState != nil {
                return performViewportUndo()
            }
            guard let textView, textView.undoManager?.canUndo == true else { return false }
            textView.undoManager?.undo()
            return true
        }

        func performRedoRequest() -> Bool {
            if viewportState != nil {
                return performViewportRedo()
            }
            guard let textView, textView.undoManager?.canRedo == true else { return false }
            textView.undoManager?.redo()
            return true
        }

        func canPerformUndoRequest() -> Bool {
            if viewportState != nil {
                return !viewportUndoStack.isEmpty
            }
            return textView?.undoManager?.canUndo ?? false
        }

        func canPerformRedoRequest() -> Bool {
            if viewportState != nil {
                return !viewportRedoStack.isEmpty
            }
            return textView?.undoManager?.canRedo ?? false
        }

        private func performViewportUndo() -> Bool {
            guard let viewport = viewportState else { return false }
            guard let group = viewportUndoStack.popLast(), !group.edits.isEmpty else { return false }

            isApplyingViewportHistory = true
            defer { isApplyingViewportHistory = false }

            var earliestInvalidation = Int.max
            for edit in group.edits.reversed() {
                let replaceRange = edit.startLine ..< edit.startLine + edit.newLines.count
                _ = viewport.backingStore.replaceLines(in: replaceRange, with: edit.oldLines)
                adjustViewportRangeForReplacement(
                    startLine: edit.startLine,
                    replacedLineCount: edit.newLines.count,
                    insertedLineCount: edit.oldLines.count
                )
                earliestInvalidation = min(earliestInvalidation, edit.startLine)
            }
            if earliestInvalidation != Int.max {
                invalidateSyntaxHighlightsFromLine(earliestInvalidation)
            }
            state.backingStoreVersion += 1
            lastSyncedBackingStoreVersion = state.backingStoreVersion
            state.markModified()
            state.notifyLanguageServerChanged()
            invalidateRenderedViewportText()
            scheduleMarkdownPreviewRefresh(immediate: true)
            appendViewportRedo(group)
            if let selection = group.edits.first?.selectionBefore {
                applyViewportHistorySelection(selection)
            }
            lastViewportEditTimestamp = nil
            return true
        }

        private func performViewportRedo() -> Bool {
            guard let viewport = viewportState else { return false }
            guard let group = viewportRedoStack.popLast(), !group.edits.isEmpty else { return false }

            isApplyingViewportHistory = true
            defer { isApplyingViewportHistory = false }

            var earliestInvalidation = Int.max
            for edit in group.edits {
                let replaceRange = edit.startLine ..< edit.startLine + edit.oldLines.count
                _ = viewport.backingStore.replaceLines(in: replaceRange, with: edit.newLines)
                adjustViewportRangeForReplacement(
                    startLine: edit.startLine,
                    replacedLineCount: edit.oldLines.count,
                    insertedLineCount: edit.newLines.count
                )
                earliestInvalidation = min(earliestInvalidation, edit.startLine)
            }
            if earliestInvalidation != Int.max {
                invalidateSyntaxHighlightsFromLine(earliestInvalidation)
            }
            state.backingStoreVersion += 1
            lastSyncedBackingStoreVersion = state.backingStoreVersion
            state.markModified()
            state.notifyLanguageServerChanged()
            invalidateRenderedViewportText()
            scheduleMarkdownPreviewRefresh(immediate: true)
            appendViewportUndo(group)
            if let selection = group.edits.last?.selectionAfter {
                applyViewportHistorySelection(selection)
            }
            lastViewportEditTimestamp = nil
            return true
        }

        private func pushViewportEdit(_ edit: ViewportEdit) {
            let now = CFAbsoluteTimeGetCurrent()
            if shouldCoalesceViewportEdit(edit, now: now), var group = viewportUndoStack.popLast() {
                group.edits.append(edit)
                viewportUndoStack.append(group)
            } else {
                appendViewportUndo(ViewportEditGroup(edits: [edit]))
            }
            viewportRedoStack.removeAll(keepingCapacity: false)
            lastViewportEditTimestamp = now
        }

        private func appendViewportUndo(_ group: ViewportEditGroup) {
            viewportUndoStack.append(group)
            if viewportUndoStack.count > Self.viewportUndoLimit {
                viewportUndoStack.removeFirst(viewportUndoStack.count - Self.viewportUndoLimit)
            }
        }

        private func appendViewportRedo(_ group: ViewportEditGroup) {
            viewportRedoStack.append(group)
            if viewportRedoStack.count > Self.viewportUndoLimit {
                viewportRedoStack.removeFirst(viewportRedoStack.count - Self.viewportUndoLimit)
            }
        }

        private func shouldCoalesceViewportEdit(_ edit: ViewportEdit, now: CFAbsoluteTime) -> Bool {
            guard let lastTimestamp = lastViewportEditTimestamp else { return false }
            guard now - lastTimestamp <= Self.viewportUndoCoalesceInterval else { return false }
            guard let lastEdit = viewportUndoStack.last?.edits.last else { return false }
            return lastEdit.selectionAfter.line == edit.selectionBefore.line
                && lastEdit.selectionAfter.column == edit.selectionBefore.column
        }

        private func adjustViewportRangeForReplacement(
            startLine: Int,
            replacedLineCount: Int,
            insertedLineCount: Int
        ) {
            guard let viewport = viewportState else { return }
            let lineDelta = insertedLineCount - replacedLineCount
            guard lineDelta != 0 else { return }

            let changeEnd = startLine + replacedLineCount
            var newStart = viewport.viewportStartLine
            var newEnd = viewport.viewportEndLine

            if changeEnd <= newStart {
                newStart += lineDelta
                newEnd += lineDelta
            } else if startLine < newEnd {
                newEnd += lineDelta
            }

            let maxLine = max(1, viewport.visualLineCount)
            newStart = max(0, min(newStart, maxLine - 1))
            newEnd = max(newStart + 1, min(newEnd, maxLine))
            viewport.applyViewport(newStart ..< newEnd)
        }

        private func applyViewportHistorySelection(_ selection: ViewportCursor) {
            updateContainerHeight()
            scrollToGlobalLine(selection.line, column: selection.column)
        }

        private func captureViewportPendingEdit(
            textView: NSTextView,
            affectedCharRange: NSRange,
            replacementString: String?
        ) {
            pendingViewportEdit = nil
            guard let viewport = viewportState else { return }

            let content = textView.string as NSString
            guard isValidEditRange(affectedCharRange, textLength: content.length) else { return }
            guard let selectionBefore = globalCursorFromLocalLocation(textView.selectedRange().location) else { return }
            guard !lineStartOffsets.isEmpty else { return }

            let safeStart = min(max(0, affectedCharRange.location), content.length)
            let safeEnd = min(content.length, NSMaxRange(affectedCharRange))
            let startLocalLine = max(0, lineNumber(atCharacterLocation: safeStart) - 1)
            let endLocalLine = max(startLocalLine, lineNumber(atCharacterLocation: safeEnd) - 1)
            let maxLocalLine = lineStartOffsets.count - 1
            let clampedStartLocalLine = min(startLocalLine, maxLocalLine)
            let clampedEndLocalLine = min(endLocalLine, maxLocalLine)

            let globalStartLine = viewport.backingStoreLine(forViewportLine: clampedStartLocalLine)
            let globalEndLine = viewport.backingStoreLine(forViewportLine: clampedEndLocalLine)
            let oldRange = globalStartLine ..< globalEndLine + 1
            let oldLines = oldRange.map { viewport.backingStore.line(at: $0) }
            guard !oldLines.isEmpty else { return }

            let oldBlock = oldLines.joined(separator: "\n") as NSString
            let blockStartOffset = lineStartOffsets[clampedStartLocalLine]
            let relativeRange = NSRange(
                location: affectedCharRange.location - blockStartOffset,
                length: affectedCharRange.length
            )
            guard isValidEditRange(relativeRange, textLength: oldBlock.length) else { return }

            let replacement = replacementString ?? ""
            let isAppendOnlyTrailingNewline = affectedCharRange.location == content.length
                && affectedCharRange.length == 0
                && replacement == "\n"
                && clampedStartLocalLine == maxLocalLine
                && oldLines.count == 1
                && oldLines[0].isEmpty
            let newLines: [String]
            if isAppendOnlyTrailingNewline {
                newLines = [""]
            } else {
                let newBlock = oldBlock.replacingCharacters(in: relativeRange, with: replacement)
                newLines = newBlock.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            }

            pendingViewportEdit = PendingViewportEdit(
                startLine: globalStartLine,
                oldLines: isAppendOnlyTrailingNewline ? [] : oldLines,
                newLines: newLines,
                selectionBefore: selectionBefore
            )
        }

        private func applyPendingEdit(_ edit: PendingViewportEdit, to store: TextBackingStore) {
            if edit.oldLines.isEmpty {
                store.insertLines(edit.newLines, at: edit.startLine)
                return
            }
            let oldRange = edit.startLine ..< edit.startLine + edit.oldLines.count
            _ = store.replaceLines(in: oldRange, with: edit.newLines)
        }

        private func globalCursorFromLocalLocation(_ location: Int) -> ViewportCursor? {
            guard let viewport = viewportState, let textView, !lineStartOffsets.isEmpty else { return nil }
            let content = textView.string as NSString
            let safeLocation = min(max(0, location), content.length)
            let localLine = lineNumber(atCharacterLocation: safeLocation)
            let localLineIndex = max(0, min(localLine - 1, lineStartOffsets.count - 1))
            let lineStart = lineStartOffsets[localLineIndex]
            let column = max(0, safeLocation - lineStart)
            let globalLine = viewport.backingStoreLine(forViewportLine: localLineIndex)
            return ViewportCursor(line: globalLine, column: column)
        }

        private func scrollCursorVisibleInViewport(textView: NSTextView, cursorLocation: Int) {
            guard let scrollView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else { return }

            let content = textView.string as NSString
            let safeLoc = min(cursorLocation, content.length)
            layoutManager.ensureLayout(forCharacterRange: NSRange(location: safeLoc, length: 0))
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: safeLoc, length: 0),
                actualCharacterRange: nil
            )
            var cursorRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            cursorRect.origin.y += textView.textContainerOrigin.y + textView.frame.origin.y

            let clipBounds = scrollView.contentView.bounds
            let visibleMinY = clipBounds.origin.y
            let visibleMaxY = visibleMinY + clipBounds.height

            if cursorRect.maxY > visibleMaxY {
                let newY = cursorRect.maxY - clipBounds.height
                scrollView.contentView.setBoundsOrigin(NSPoint(x: clipBounds.origin.x, y: newY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            } else if cursorRect.origin.y < visibleMinY {
                scrollView.contentView.setBoundsOrigin(NSPoint(x: clipBounds.origin.x, y: cursorRect.origin.y))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard !isUpdating else { return true }
            if handleAutoClosingPair(
                textView: textView,
                affectedCharRange: affectedCharRange,
                replacementString: replacementString
            ) {
                return false
            }
            captureViewportPendingEdit(
                textView: textView,
                affectedCharRange: affectedCharRange,
                replacementString: replacementString
            )
            if replacementString?.contains("\n") == true {
                scheduleMarkdownPreviewRefresh(immediate: true)
            }
            return true
        }

        private func handleAutoClosingPair(
            textView: NSTextView,
            affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard lastAppearance.autoClosesPairs else { return false }
            guard affectedCharRange.length == 0, let replacementString, replacementString.count == 1 else { return false }
            if shouldOvertypeClosingPair(textView: textView, location: affectedCharRange.location, replacementString: replacementString) {
                textView.setSelectedRange(NSRange(location: affectedCharRange.location + 1, length: 0))
                return true
            }
            guard let closing = closingPair(for: replacementString) else { return false }
            let selected = textView.selectedRange()
            guard selected.location != NSNotFound else { return false }
            if selected.length > 0 {
                let content = textView.string as NSString
                guard NSMaxRange(selected) <= content.length else { return false }
                let wrapped = replacementString + content.substring(with: selected) + closing
                textView.insertText(wrapped, replacementRange: selected)
                textView.setSelectedRange(NSRange(location: selected.location + replacementString.count, length: selected.length))
                return true
            }
            textView.insertText(replacementString + closing, replacementRange: affectedCharRange)
            textView.setSelectedRange(NSRange(location: affectedCharRange.location + replacementString.count, length: 0))
            return true
        }

        private func shouldOvertypeClosingPair(textView: NSTextView, location: Int, replacementString: String) -> Bool {
            guard isClosingPairCharacter(replacementString) else { return false }
            let content = textView.string as NSString
            guard location < content.length else { return false }
            let next = content.substring(with: NSRange(location: location, length: 1))
            return next == replacementString
        }

        private func closingPair(for opening: String) -> String? {
            languagePairs().first { $0.open == opening }?.close
        }

        private func isClosingPairCharacter(_ value: String) -> Bool {
            languagePairs().contains { $0.close == value }
        }

        private func isPair(open: unichar, close: unichar) -> Bool {
            languagePairMap()[open] == close
        }

        private func languagePairs() -> [(open: String, close: String)] {
            let configured = LanguageRegistry.shared.configuration(forFile: state.filePath)?.autoClosingPairs ?? []
            let pairs = configured.compactMap { pair -> (open: String, close: String)? in
                guard pair.count == 2, pair[0].utf16.count == 1, pair[1].utf16.count == 1 else { return nil }
                return (pair[0], pair[1])
            }
            guard !pairs.isEmpty else {
                return [("(", ")"), ("[", "]"), ("{", "}"), ("\"", "\""), ("'", "'")]
            }
            return pairs
        }

        private func languagePairMap() -> [unichar: unichar] {
            Dictionary(uniqueKeysWithValues: languagePairs().compactMap { pair in
                guard let open = pair.open.utf16.first, let close = pair.close.utf16.first else { return nil }
                return (open, close)
            })
        }

        func textViewDidChangeSelection(_: Notification) {
            guard let textView, !isUpdating else { return }
            let range = textView.selectedRange()
            let content = textView.string as NSString
            let loc = min(range.location, content.length)

            let localLine = lineNumber(atCharacterLocation: loc)
            let localLineIndex = localLine - 1

            let globalLine = viewportState?.backingStoreLine(forViewportLine: localLineIndex) ?? localLine
            let localLineStart = lineStartOffsets[max(0, min(localLineIndex, lineStartOffsets.count - 1))]
            state.updateCursorPosition(
                line: globalLine + 1,
                column: loc - localLineStart + 1,
                selectionLength: range.length
            )

            updateCurrentSelection(in: textView, range: range)
            refreshEditorDecorations()
        }

        private func handleMoveAtViewportBoundary(direction: Int) -> Bool {
            guard let viewport = viewportState, let textView else { return false }
            let range = textView.selectedRange()
            let content = textView.string as NSString
            let loc = min(range.location, content.length)
            let localLine = lineNumber(atCharacterLocation: loc)
            let localLineIndex = localLine - 1
            let totalLocalLines = lineStartOffsets.count

            let atFirstLine = localLineIndex <= 0
            let atLastLine = localLineIndex >= totalLocalLines - 1

            if direction < 0, atFirstLine, viewport.viewportStartLine > 0 {
                let lineStart = lineStartOffsets[max(0, min(localLineIndex, lineStartOffsets.count - 1))]
                let column = max(0, loc - lineStart)
                let globalLine = viewport.backingStoreLine(forViewportLine: localLineIndex)
                let targetGlobalLine = max(0, globalLine - 1)
                scrollToGlobalLine(targetGlobalLine, column: column)
                return true
            }

            if direction > 0, atLastLine, viewport.viewportEndLine < viewport.visualLineCount {
                let lineStart = lineStartOffsets[max(0, min(localLineIndex, lineStartOffsets.count - 1))]
                let column = max(0, loc - lineStart)
                let targetGlobalLine = viewport.backingStoreLine(forViewportLine: localLineIndex + 1)
                scrollToGlobalLine(targetGlobalLine, column: column)
                return true
            }

            return false
        }

        private func scrollToGlobalLine(_ globalLine: Int, column: Int) {
            guard let viewport = viewportState, let scrollView, let textView else { return }

            let targetScrollY = viewport.scrollY(forLine: globalLine)
            let visibleHeight = scrollView.contentView.bounds.height
            let currentScrollY = scrollView.contentView.bounds.origin.y

            let lineTop = targetScrollY
            let lineBottom = targetScrollY + viewport.estimatedLineHeight

            var newScrollY = currentScrollY
            if lineBottom > currentScrollY + visibleHeight {
                newScrollY = lineBottom - visibleHeight
            } else if lineTop < currentScrollY {
                newScrollY = lineTop
            }

            let maxScrollY = max(0, viewport.totalDocumentHeight - visibleHeight)
            if viewport.scrollY(forLine: globalLine) >= maxScrollY {
                newScrollY = maxScrollY
            } else {
                newScrollY = min(maxScrollY, max(0, newScrollY))
            }

            scrollView.contentView.setBoundsOrigin(NSPoint(x: scrollView.contentView.bounds.origin.x, y: newScrollY))
            scrollView.reflectScrolledClipView(scrollView.contentView)

            refreshViewport(force: true)
            rebuildLineStartOffsetsForViewport()

            guard let newLocalLine = viewport.viewportLine(forBackingStoreLine: globalLine) else { return }
            let newCharOffset = charOffsetForLocalLine(newLocalLine)
            let newContent = textView.string as NSString
            let lineRange = newContent.lineRange(for: NSRange(location: min(newCharOffset, newContent.length), length: 0))
            let lineLength = lineRange.length - (NSMaxRange(lineRange) < newContent.length ? 1 : 0)
            let newCursor = newCharOffset + min(column, max(0, lineLength))
            let safeCursor = min(newCursor, newContent.length)

            isUpdating = true
            textView.setSelectedRange(NSRange(location: safeCursor, length: 0))
            isUpdating = false

            let cursorLineStart = lineStartOffsets[max(0, min(newLocalLine, lineStartOffsets.count - 1))]
            state.updateCursorPosition(
                line: globalLine + 1,
                column: safeCursor - cursorLineStart + 1,
                selectionLength: 0
            )
        }

        private func updateCurrentSelection(in textView: NSTextView, range: NSRange) {
            guard range.length > 0, range.length <= 200 else {
                state.currentSelection = ""
                return
            }
            let nsContent = textView.string as NSString
            guard NSMaxRange(range) <= nsContent.length else {
                state.currentSelection = ""
                return
            }
            let selected = nsContent.substring(with: range)
            if selected.contains("\n") {
                state.currentSelection = ""
                return
            }
            state.currentSelection = selected
        }

        // MARK: - Line Start Offsets

        private func isValidEditRange(_ range: NSRange, textLength: Int) -> Bool {
            guard range.location != NSNotFound else { return false }
            guard range.location >= 0, range.length >= 0 else { return false }
            guard range.location <= textLength else { return false }
            guard range.length <= textLength - range.location else { return false }
            return true
        }

        func lineNumber(atCharacterLocation location: Int) -> Int {
            guard !lineStartOffsets.isEmpty else { return 1 }
            var low = 0
            var high = lineStartOffsets.count - 1
            var result = 0

            while low <= high {
                let mid = (low + high) / 2
                if lineStartOffsets[mid] <= location {
                    result = mid
                    low = mid + 1
                    continue
                }
                if mid == 0 { break }
                high = mid - 1
            }

            return result + 1
        }

        func handleKeyDown(_ event: NSEvent) -> Bool {
            guard let characters = event.charactersIgnoringModifiers?.lowercased(), !characters.isEmpty else { return false }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command, characters == "d" {
                return selectNextOccurrence()
            }
            if flags == .command, characters == "l" {
                return selectCurrentLine()
            }
            if flags == [.command, .shift], characters == "d" {
                return duplicateCurrentLineOrSelection()
            }
            if flags == [.option, .shift], event.keyCode == 126 {
                return duplicateLineWithDirection(direction: -1)
            }
            if flags == [.option, .shift], event.keyCode == 125 {
                return duplicateLineWithDirection(direction: 1)
            }
            if flags == .command, characters == "/" {
                return toggleLineComment()
            }
            if flags == [.option, .command], event.keyCode == 126 {
                return moveCurrentLines(direction: -1)
            }
            if flags == [.option, .command], event.keyCode == 125 {
                return moveCurrentLines(direction: 1)
            }
            return false
        }

        private func selectCurrentLine() -> Bool {
            guard let textView else { return false }
            let content = textView.string as NSString
            let location = min(textView.selectedRange().location, content.length)
            let lineRange = content.lineRange(for: NSRange(location: location, length: 0))
            textView.setSelectedRange(lineRange)
            return true
        }

        private func selectNextOccurrence() -> Bool {
            guard let textView else { return false }
            let content = textView.string as NSString
            let selectedRange = textView.selectedRange()
            let selectedText: String
            if selectedRange.length > 0, NSMaxRange(selectedRange) <= content.length {
                selectedText = content.substring(with: selectedRange)
            } else {
                guard let wordRange = wordRange(at: selectedRange.location, content: content) else { return false }
                selectedText = content.substring(with: wordRange)
                textView.setSelectedRange(wordRange)
            }
            guard !selectedText.isEmpty, !selectedText.contains("\n") else { return false }
            let searchStart = min(NSMaxRange(textView.selectedRange()), content.length)
            let tailRange = NSRange(location: searchStart, length: content.length - searchStart)
            var match = content.range(of: selectedText, options: [], range: tailRange)
            if match.location == NSNotFound {
                match = content.range(of: selectedText, options: [], range: NSRange(location: 0, length: searchStart))
            }
            guard match.location != NSNotFound else { return false }
            textView.setSelectedRange(match)
            textView.scrollRangeToVisible(match)
            return true
        }

        private func duplicateCurrentLineOrSelection() -> Bool {
            guard let textView else { return false }
            let content = textView.string as NSString
            let range = textView.selectedRange()
            guard range.location != NSNotFound else { return false }
            if range.length > 0, NSMaxRange(range) <= content.length {
                let selected = content.substring(with: range)
                textView.insertText(selected, replacementRange: NSRange(location: NSMaxRange(range), length: 0))
                textView.setSelectedRange(NSRange(location: NSMaxRange(range), length: range.length))
                return true
            }
            let lineRange = content.lineRange(for: NSRange(location: min(range.location, content.length), length: 0))
            let line = content.substring(with: lineRange)
            textView.insertText(line, replacementRange: NSRange(location: NSMaxRange(lineRange), length: 0))
            textView.setSelectedRange(NSRange(location: NSMaxRange(lineRange), length: 0))
            return true
        }

        private func duplicateLineWithDirection(direction: Int) -> Bool {
            guard let textView else { return false }
            let content = textView.string as NSString
            let range = textView.selectedRange()
            guard range.location != NSNotFound else { return false }
            let lineRange = content.lineRange(for: NSRange(location: min(range.location, content.length), length: 0))
            let line = content.substring(with: lineRange)
            if direction < 0 {
                textView.insertText(line, replacementRange: NSRange(location: lineRange.location, length: 0))
                textView.setSelectedRange(NSRange(location: lineRange.location, length: 0))
                return true
            }
            textView.insertText(line, replacementRange: NSRange(location: NSMaxRange(lineRange), length: 0))
            textView.setSelectedRange(NSRange(location: NSMaxRange(lineRange), length: 0))
            return true
        }

        private func moveCurrentLines(direction: Int) -> Bool {
            guard let textView else { return false }
            let content = textView.string as NSString
            let selection = textView.selectedRange()
            guard selection.location != NSNotFound else { return false }
            let selectedLines = selectedLineRanges(content: content, range: selection)
            guard let firstLine = selectedLines.first, let lastLine = selectedLines.last else { return false }
            if direction < 0 {
                guard firstLine.location > 0 else { return true }
                let previousLine = content.lineRange(for: NSRange(location: firstLine.location - 1, length: 0))
                let blockRange = NSRange(location: firstLine.location, length: NSMaxRange(lastLine) - firstLine.location)
                let previousText = content.substring(with: previousLine)
                let blockText = content.substring(with: blockRange)
                textView.insertText(blockText + previousText, replacementRange: NSRange(location: previousLine.location, length: previousLine.length + blockRange.length))
                textView.setSelectedRange(NSRange(location: previousLine.location, length: blockRange.length))
                return true
            }
            guard NSMaxRange(lastLine) < content.length else { return true }
            let nextLine = content.lineRange(for: NSRange(location: NSMaxRange(lastLine), length: 0))
            let blockRange = NSRange(location: firstLine.location, length: NSMaxRange(lastLine) - firstLine.location)
            let blockText = content.substring(with: blockRange)
            let nextText = content.substring(with: nextLine)
            textView.insertText(nextText + blockText, replacementRange: NSRange(location: blockRange.location, length: blockRange.length + nextLine.length))
            textView.setSelectedRange(NSRange(location: firstLine.location + nextLine.length, length: blockRange.length))
            return true
        }

        private func wordRange(at location: Int, content: NSString) -> NSRange? {
            guard content.length > 0 else { return nil }
            let safe = min(max(0, location), content.length - 1)
            let charset = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
            var start = safe
            while start > 0, let scalar = Unicode.Scalar(content.character(at: start - 1)), charset.contains(scalar) {
                start -= 1
            }
            var end = safe
            while end < content.length, let scalar = Unicode.Scalar(content.character(at: end)), charset.contains(scalar) {
                end += 1
            }
            guard end > start else { return nil }
            return NSRange(location: start, length: end - start)
        }

        private func toggleLineComment() -> Bool {
            guard let textView else { return false }
            guard let marker = LanguageRegistry.shared.configuration(forFile: state.filePath)?.comments?.lineComment else { return false }
            let content = textView.string as NSString
            let selection = textView.selectedRange()
            guard selection.location != NSNotFound else { return false }
            let lineRanges = selectedLineRanges(content: content, range: selection)
            guard !lineRanges.isEmpty else { return false }
            let shouldUncomment = lineRanges.allSatisfy { lineRange in
                let line = content.substring(with: lineRange)
                let prefix = leadingWhitespace(in: line)
                return line.dropFirst(prefix.count).hasPrefix(marker)
            }
            for lineRange in lineRanges.reversed() {
                let line = content.substring(with: lineRange)
                let prefix = leadingWhitespace(in: line)
                let markerLocation = lineRange.location + prefix.count
                if shouldUncomment {
                    let removeLength = line.dropFirst(prefix.count).hasPrefix(marker + " ") ? marker.count + 1 : marker.count
                    textView.insertText("", replacementRange: NSRange(location: markerLocation, length: removeLength))
                } else {
                    textView.insertText(marker + " ", replacementRange: NSRange(location: markerLocation, length: 0))
                }
            }
            return true
        }

        func textView(_: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let textView else { return false }
            if commandSelector == Self.undoCommandSelector {
                return performUndoRequest()
            }
            if commandSelector == Self.redoCommandSelector {
                return performRedoRequest()
            }
            if commandSelector == Self.indentCommandSelector {
                return handleIndent(textView)
            }
            if commandSelector == Self.outdentCommandSelector {
                return handleOutdent(textView)
            }
            if commandSelector == Self.newlineCommandSelector, lastAppearance.autoIndentsNewLines {
                return handleAutoIndentedNewline(textView)
            }
            if commandSelector == Self.moveToBeginningOfLineSelector {
                return handleSmartHome(textView)
            }
            if commandSelector == Self.moveToEndOfLineSelector {
                return handleSmartEnd(textView)
            }
            if commandSelector == Self.deleteBackwardSelector, lastAppearance.autoClosesPairs {
                return handlePairedDelete(textView)
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)), state.searchVisible {
                state.searchVisible = false
                return true
            }
            if commandSelector == #selector(NSResponder.deleteWordBackward(_:)) {
                return handleDeleteWordBackward(textView)
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                return handleMoveAtViewportBoundary(direction: -1)
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                return handleMoveAtViewportBoundary(direction: 1)
            }
            return false
        }

        private func handleIndent(_ textView: NSTextView) -> Bool {
            let range = textView.selectedRange()
            guard range.location != NSNotFound else { return false }
            let unit = indentUnit()
            let content = textView.string as NSString
            guard range.length > 0, selectedTextContainsNewline(textView, range: range) else {
                textView.insertText(unit, replacementRange: range)
                return true
            }
            let lineRanges = selectedLineRanges(content: content, range: range)
            guard !lineRanges.isEmpty else { return false }
            var inserted = 0
            for lineRange in lineRanges.reversed() {
                textView.insertText(unit, replacementRange: NSRange(location: lineRange.location, length: 0))
                inserted += unit.count
            }
            textView.setSelectedRange(NSRange(location: range.location, length: range.length + inserted))
            return true
        }

        private func handleOutdent(_ textView: NSTextView) -> Bool {
            let range = textView.selectedRange()
            guard range.location != NSNotFound else { return false }
            let content = textView.string as NSString
            let lineRanges = selectedLineRanges(content: content, range: range)
            guard !lineRanges.isEmpty else { return false }
            let unitLength = indentUnit().count
            var removedBeforeSelection = 0
            var removedInsideSelection = 0
            for lineRange in lineRanges.reversed() {
                let removal = outdentRange(content: content, lineRange: lineRange, maxColumns: unitLength)
                guard removal.length > 0 else { continue }
                textView.insertText("", replacementRange: removal)
                if removal.location < range.location {
                    removedBeforeSelection += removal.length
                } else {
                    removedInsideSelection += removal.length
                }
            }
            let newLocation = max(0, range.location - removedBeforeSelection)
            let newLength = max(0, range.length - removedInsideSelection)
            textView.setSelectedRange(NSRange(location: newLocation, length: newLength))
            return true
        }

        private func handleAutoIndentedNewline(_ textView: NSTextView) -> Bool {
            let range = textView.selectedRange()
            guard range.location != NSNotFound else { return false }
            let content = textView.string as NSString
            let cursor = min(range.location, content.length)
            let lineRange = content.lineRange(for: NSRange(location: cursor, length: 0))
            let linePrefixLength = max(0, cursor - lineRange.location)
            let linePrefix = content.substring(with: NSRange(location: lineRange.location, length: linePrefixLength))
            var indent = leadingWhitespace(in: linePrefix)
            if shouldIncreaseIndent(after: linePrefix) {
                indent += indentUnit()
            }
            if shouldDecreaseIndent(before: content, cursor: cursor) {
                let unit = indentUnit()
                if indent.hasSuffix(unit) {
                    indent.removeLast(unit.count)
                }
            }
            textView.insertText("\n" + indent, replacementRange: range)
            return true
        }

        private func handleSmartHome(_ textView: NSTextView) -> Bool {
            let content = textView.string as NSString
            let range = textView.selectedRange()
            guard range.location != NSNotFound else { return false }
            let cursor = min(range.location, content.length)
            let lineRange = content.lineRange(for: NSRange(location: cursor, length: 0))
            let line = content.substring(with: lineRange)
            let firstNonWhitespace = lineRange.location + leadingWhitespace(in: line).count
            let target = cursor == firstNonWhitespace ? lineRange.location : firstNonWhitespace
            textView.setSelectedRange(NSRange(location: target, length: 0))
            return true
        }

        private func handleSmartEnd(_ textView: NSTextView) -> Bool {
            let content = textView.string as NSString
            let range = textView.selectedRange()
            guard range.location != NSNotFound else { return false }
            let cursor = min(range.location, content.length)
            let lineRange = content.lineRange(for: NSRange(location: cursor, length: 0))
            let lineEnd = lineRange.location + max(0, lineRange.length - (NSMaxRange(lineRange) < content.length ? 1 : 0))
            textView.setSelectedRange(NSRange(location: lineEnd, length: 0))
            return true
        }

        private func handlePairedDelete(_ textView: NSTextView) -> Bool {
            let range = textView.selectedRange()
            guard range.location != NSNotFound, range.length == 0, range.location > 0 else { return false }
            let content = textView.string as NSString
            guard range.location < content.length else { return false }
            let previous = content.character(at: range.location - 1)
            let next = content.character(at: range.location)
            guard isPair(open: previous, close: next) else { return false }
            textView.insertText("", replacementRange: NSRange(location: range.location - 1, length: 2))
            return true
        }

        private func selectedTextContainsNewline(_ textView: NSTextView, range: NSRange) -> Bool {
            let content = textView.string as NSString
            guard NSMaxRange(range) <= content.length else { return false }
            return content.substring(with: range).contains("\n")
        }

        private func selectedLineRanges(content: NSString, range: NSRange) -> [NSRange] {
            let safeLocation = min(range.location, content.length)
            let endLocation = min(NSMaxRange(range), content.length)
            let effectiveEnd = range.length > 0 && endLocation > safeLocation ? max(safeLocation, endLocation - 1) : safeLocation
            let selectedRange = NSRange(location: safeLocation, length: max(0, effectiveEnd - safeLocation))
            let fullLineRange = content.lineRange(for: selectedRange)
            var ranges: [NSRange] = []
            var location = fullLineRange.location
            while location < NSMaxRange(fullLineRange), location <= content.length {
                let lineRange = content.lineRange(for: NSRange(location: min(location, content.length), length: 0))
                ranges.append(lineRange)
                let next = NSMaxRange(lineRange)
                if next <= location { break }
                location = next
            }
            return ranges
        }

        private func outdentRange(content: NSString, lineRange: NSRange, maxColumns: Int) -> NSRange {
            guard lineRange.location < content.length else { return NSRange(location: lineRange.location, length: 0) }
            var length = 0
            var columns = 0
            let maxLocation = min(NSMaxRange(lineRange), content.length)
            while lineRange.location + length < maxLocation, columns < maxColumns {
                let char = content.character(at: lineRange.location + length)
                if char == 0x20 {
                    length += 1
                    columns += 1
                    continue
                }
                if char == 0x09 {
                    length += 1
                    break
                }
                break
            }
            return NSRange(location: lineRange.location, length: length)
        }

        private func leadingWhitespace(in text: String) -> String {
            var output = ""
            for character in text {
                guard character == " " || character == "\t" else { break }
                output.append(character)
            }
            return output
        }

        private func shouldIncreaseIndent(after linePrefix: String) -> Bool {
            if let pattern = LanguageRegistry.shared.configuration(forFile: state.filePath)?.indentationRules?.increaseIndentPattern,
               regexMatches(pattern, linePrefix)
            {
                return true
            }
            let trimmed = linePrefix.trimmingCharacters(in: .whitespaces)
            return trimmed.hasSuffix("{") || trimmed.hasSuffix("[") || trimmed.hasSuffix("(") || trimmed.hasSuffix(":")
        }

        private func shouldDecreaseIndent(before content: NSString, cursor: Int) -> Bool {
            guard let pattern = LanguageRegistry.shared.configuration(forFile: state.filePath)?.indentationRules?.decreaseIndentPattern else { return false }
            guard cursor < content.length else { return false }
            let lineRange = content.lineRange(for: NSRange(location: cursor, length: 0))
            let suffixLocation = cursor
            let suffixLength = max(0, NSMaxRange(lineRange) - suffixLocation)
            guard suffixLength > 0 else { return false }
            return regexMatches(pattern, content.substring(with: NSRange(location: suffixLocation, length: suffixLength)))
        }

        private func regexMatches(_ pattern: String, _ text: String) -> Bool {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            let range = NSRange(location: 0, length: (text as NSString).length)
            return regex.firstMatch(in: text, range: range) != nil
        }

        private func indentUnit() -> String {
            String(repeating: " ", count: max(1, lastAppearance.tabSize))
        }

        private func handleDeleteWordBackward(_ textView: NSTextView) -> Bool {
            let content = textView.string
            let range = textView.selectedRange()
            guard range.location != NSNotFound, range.location > 0 else { return false }
            textView.breakUndoCoalescing()

            let nsContent = content as NSString
            let cursorPos = range.location
            let charBefore = nsContent.character(at: cursorPos - 1)

            if charBefore == 0x0A {
                let deleteRange = NSRange(location: cursorPos - 1, length: 1)
                textView.insertText("", replacementRange: deleteRange)
                return true
            }

            let scalar = Unicode.Scalar(charBefore)
            if let scalar, CharacterSet.punctuationCharacters.union(.symbols).contains(scalar) {
                let deleteRange = NSRange(location: cursorPos - 1, length: 1)
                textView.insertText("", replacementRange: deleteRange)
                return true
            }

            let lineRange = nsContent.lineRange(for: NSRange(location: cursorPos, length: 0))
            let lineStart = lineRange.location
            let textBeforeCursor = nsContent.substring(with: NSRange(location: lineStart, length: cursorPos - lineStart))

            if textBeforeCursor.allSatisfy({ $0 == " " || $0 == "\t" }) {
                let deleteRange = NSRange(location: lineStart, length: cursorPos - lineStart)
                textView.insertText("", replacementRange: deleteRange)
                return true
            }

            return false
        }
    }
}
