import AppKit
import SwiftUI

struct DiffLineMetadata {
    let kind: DiffDisplayRow.Kind
    let oldLineNumber: Int?
    let newLineNumber: Int?
}

enum DiffGutterMode {
    case unified
    case singleOld
    case singleNew
}

final class DiffBackgroundLayoutManager: NSLayoutManager {
    var lineBackgrounds: [NSColor?] = []

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        guard let textContainer = textContainers.first,
              let storage = textStorage
        else { return }

        guard glyphsToShow.location != NSNotFound,
              glyphsToShow.length > 0
        else { return }

        let glyphCount = numberOfGlyphs
        guard glyphCount > 0 else { return }

        let safeGlyphRange = NSIntersectionRange(glyphsToShow, NSRange(location: 0, length: glyphCount))
        guard safeGlyphRange.length > 0 else { return }

        let fullText = storage.string as NSString
        let startCharIndex = characterIndexForGlyph(at: safeGlyphRange.location)
        var lineIndex = 0
        var pos = 0
        while pos < startCharIndex, pos < fullText.length {
            if fullText.character(at: pos) == 0x0A {
                lineIndex += 1
            }
            pos += 1
        }

        enumerateLineFragments(forGlyphRange: safeGlyphRange) { [self] _, usedRect, _, _, _ in
            if lineIndex < self.lineBackgrounds.count,
               let bgColor = self.lineBackgrounds[lineIndex]
            {
                bgColor.setFill()
                let rect = NSRect(
                    x: usedRect.origin.x + origin.x - textContainer.lineFragmentPadding,
                    y: usedRect.origin.y + origin.y,
                    width: max(usedRect.width + textContainer.lineFragmentPadding * 2, textContainer.size.width),
                    height: usedRect.height
                )
                rect.fill()
            }
            lineIndex += 1
        }
    }
}

func buildLineBackgrounds(
    metadata: [DiffLineMetadata],
    side: DiffBackgroundSide,
    theme: DiffRenderTheme
) -> [NSColor?] {
    metadata.map { meta in
        switch meta.kind {
        case .addition:
            switch side {
            case .left: nil
            case .right,
                 .both: theme.additionBackground
            }
        case .deletion:
            switch side {
            case .left,
                 .both: theme.deletionBackground
            case .right: nil
            }
        case .hunk:
            theme.hunkBackground
        case .collapsed:
            theme.collapsedBackground
        case .context:
            nil
        }
    }
}

@MainActor
enum DiffMetrics {
    static var font: NSFont {
        AppTypographySettings.shared.nsFont(size: 12)
    }

    static var glyphAdvance: CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let sample = NSAttributedString(string: "M", attributes: attrs)
        let size = sample.size()
        return size.width > 0 ? size.width : 7.2
    }

    static let horizontalPadding: CGFloat = 12

    static func expectedWidth(maxColumns: Int) -> CGFloat {
        let columns = max(maxColumns, 1)
        return ceil(CGFloat(columns) * glyphAdvance) + horizontalPadding
    }
}

final class DiffContentNSView: NSView {
    override var isFlipped: Bool { true }

    let textView: NSTextView
    let backgroundLayoutManager: DiffBackgroundLayoutManager
    var lineMetadata: [DiffLineMetadata] = []
    var diffLineHeight: CGFloat = 20
    private var expectedRowCount: Int = 0
    private var expectedWidth: CGFloat = 100

    override init(frame frameRect: NSRect) {
        backgroundLayoutManager = DiffBackgroundLayoutManager()
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(backgroundLayoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 6
        backgroundLayoutManager.addTextContainer(textContainer)

        textView = NSTextView(frame: frameRect, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width, .height]
        textView.textContainerInset = .zero
        textView.isAutomaticLinkDetectionEnabled = false

        super.init(frame: frameRect)

        addSubview(textView)
        setAccessibilityRole(.textArea)
        setAccessibilityRoleDescription("Diff Content")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Not supported")
    }

    func prepareSize(rowCount: Int, maxColumns: Int, lineHeight: CGFloat) {
        diffLineHeight = lineHeight
        expectedRowCount = rowCount
        expectedWidth = DiffMetrics.expectedWidth(maxColumns: maxColumns)

        let height = CGFloat(max(rowCount, 1)) * lineHeight
        let size = NSSize(width: expectedWidth, height: height)
        textView.setFrameSize(size)
        if let container = textView.textContainer {
            container.size = size
        }
        invalidateIntrinsicContentSize()
    }

    func configure(
        attributedString: NSAttributedString,
        metadata: [DiffLineMetadata],
        lineBackgrounds: [NSColor?],
        lineHeight: CGFloat
    ) {
        lineMetadata = metadata
        diffLineHeight = lineHeight
        backgroundLayoutManager.lineBackgrounds = lineBackgrounds

        textView.textStorage?.setAttributedString(attributedString)

        guard let container = textView.textContainer else { return }
        backgroundLayoutManager.ensureLayout(for: container)

        let usedRect = backgroundLayoutManager.usedRect(for: container)
        let height = CGFloat(max(metadata.count, 1)) * lineHeight
        let measuredWidth = usedRect.width + DiffMetrics.horizontalPadding
        let width = max(measuredWidth, expectedWidth, 100)
        expectedWidth = width
        expectedRowCount = metadata.count

        textView.setFrameSize(NSSize(width: width, height: height))
        container.size = NSSize(width: width, height: height)
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        let rowCount = max(lineMetadata.count, expectedRowCount, 1)
        let height = CGFloat(rowCount) * diffLineHeight
        guard let container = textView.textContainer else {
            return NSSize(width: max(expectedWidth, 100), height: height)
        }
        let usedRect = backgroundLayoutManager.usedRect(for: container)
        let measuredWidth = usedRect.width + DiffMetrics.horizontalPadding
        return NSSize(width: max(measuredWidth, expectedWidth, 100), height: height)
    }

    override func layout() {
        super.layout()
        textView.frame = bounds
    }
}

final class DiffGutterNSView: NSView {
    static let prefixColumnWidth: CGFloat = 16

    private enum HoveredCell: Equatable {
        case old(lineIndex: Int)
        case new(lineIndex: Int)
        case single(lineIndex: Int)
    }

    override var isFlipped: Bool { true }

    var lineMetadata: [DiffLineMetadata] = []
    var filePath: String = ""
    var mode: DiffGutterMode = .unified
    var columnWidth: CGFloat = 30
    var lineHeight: CGFloat = 20
    var cachedBorderColor: NSColor = .separatorColor
    var cachedNumberColor: NSColor = .secondaryLabelColor
    var cachedNumberHoverColor: NSColor = .labelColor
    var cachedAddColor: NSColor = .systemGreen
    var cachedRemoveColor: NSColor = .systemRed
    var onCommentRequest: ((DiffCommentAnchor, CGPoint) -> Void)?
    var comments: [DiffComment] = []
    private var commentHoverProgress: CGFloat = 0
    private var trackingArea: NSTrackingArea?
    private var hoveredCell: HoveredCell?
    var numberFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    var prefixFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    private let numberParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        return style
    }()

    private let prefixParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        updateTrackingArea()
        setAccessibilityRole(.column)
        setAccessibilityRoleDescription("Line Numbers")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Not supported")
    }

    override func accessibilityLabel() -> String? {
        "Line numbers gutter"
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTrackingArea()
    }

    private func updateTrackingArea() {
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let cell = cellAtPoint(point)
        if cell != hoveredCell {
            hoveredCell = cell
            animateCommentBubbleIfNeeded()
        }
        if cell != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with _: NSEvent) {
        if hoveredCell != nil {
            hoveredCell = nil
            commentHoverProgress = 0
            needsDisplay = true
        }
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let cell = cellAtPoint(point),
              let lineNumber = lineNumberForCell(cell)
        else { return }
        let side = sideForCell(cell)
        if let onCommentRequest, let side, let window {
            onCommentRequest(
                .line(path: filePath, side: side, lineNumber: lineNumber),
                window.convertPoint(toScreen: event.locationInWindow)
            )
            return
        }
        let reference = "\(filePath):\(lineNumber)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reference, forType: .string)
        ToastState.shared.show("Copied \(reference)")
    }

    private func cellAtPoint(_ point: NSPoint) -> HoveredCell? {
        let lineIndex = Int(point.y / lineHeight)
        guard lineIndex >= 0, lineIndex < lineMetadata.count else { return nil }

        switch mode {
        case .unified:
            if point.x <= columnWidth {
                guard lineMetadata[lineIndex].oldLineNumber != nil else { return nil }
                return .old(lineIndex: lineIndex)
            } else if point.x <= columnWidth * 2 + 1 {
                guard lineMetadata[lineIndex].newLineNumber != nil else { return nil }
                return .new(lineIndex: lineIndex)
            }
            return nil
        case .singleOld:
            guard point.x <= columnWidth, lineMetadata[lineIndex].oldLineNumber != nil else { return nil }
            return .single(lineIndex: lineIndex)
        case .singleNew:
            guard point.x <= columnWidth, lineMetadata[lineIndex].newLineNumber != nil else { return nil }
            return .single(lineIndex: lineIndex)
        }
    }

    private func lineNumberForCell(_ cell: HoveredCell) -> Int? {
        switch cell {
        case let .old(lineIndex): lineMetadata[lineIndex].oldLineNumber
        case let .new(lineIndex): lineMetadata[lineIndex].newLineNumber
        case let .single(lineIndex):
            switch mode {
            case .singleOld: lineMetadata[lineIndex].oldLineNumber
            case .singleNew: lineMetadata[lineIndex].newLineNumber
            case .unified: nil
            }
        }
    }

    private func sideForCell(_ cell: HoveredCell) -> DiffLineSide? {
        switch cell {
        case .old:
            .old
        case .new:
            .new
        case .single:
            mode == .singleOld ? .old : .new
        }
    }

    var gutterWidth: CGFloat {
        switch mode {
        case .unified: columnWidth * 2 + 2 + Self.prefixColumnWidth
        case .singleOld,
             .singleNew: columnWidth + 1
        }
    }

    override var intrinsicContentSize: NSSize {
        let height = CGFloat(max(lineMetadata.count, 1)) * lineHeight
        return NSSize(width: gutterWidth, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let totalWidth = bounds.width

        switch mode {
        case .unified:
            drawUnifiedGutter(dirtyRect, totalWidth: totalWidth)
        case .singleOld:
            drawSingleColumnGutter(dirtyRect, totalWidth: totalWidth, keyPath: \.oldLineNumber)
        case .singleNew:
            drawSingleColumnGutter(dirtyRect, totalWidth: totalWidth, keyPath: \.newLineNumber)
        }
    }

    private func numberAttrs(highlighted: Bool, commented: Bool = false) -> [NSAttributedString.Key: Any] {
        [
            .font: commented ? NSFontManager.shared.convert(numberFont, toHaveTrait: .boldFontMask) : numberFont,
            .foregroundColor: commented || highlighted ? cachedNumberHoverColor : cachedNumberColor,
            .paragraphStyle: numberParagraphStyle,
        ]
    }

    private func drawUnifiedGutter(
        _ dirtyRect: NSRect,
        totalWidth: CGFloat
    ) {
        let col1X: CGFloat = 0
        let col2X = columnWidth + 1
        let prefixX = columnWidth * 2 + 2

        cachedBorderColor.setFill()
        NSRect(x: columnWidth, y: dirtyRect.origin.y, width: 1, height: dirtyRect.height).fill()
        NSRect(x: columnWidth * 2 + 1, y: dirtyRect.origin.y, width: 1, height: dirtyRect.height).fill()

        for (index, meta) in lineMetadata.enumerated() {
            let y = CGFloat(index) * lineHeight
            guard dirtyRect.intersects(NSRect(x: 0, y: y, width: totalWidth, height: lineHeight)) else { continue }

            let textY = y + (lineHeight - numberFont.ascender + numberFont.descender) / 2

            if let old = meta.oldLineNumber {
                let isHovered = hoveredCell == .old(lineIndex: index)
                let str = NSAttributedString(
                    string: "\(old)",
                    attributes: numberAttrs(highlighted: isHovered, commented: hasLineComment(side: .old, lineNumber: old))
                )
                str.draw(in: NSRect(x: col1X, y: textY, width: columnWidth - 4, height: lineHeight))
            }
            if let new = meta.newLineNumber {
                let isHovered = hoveredCell == .new(lineIndex: index)
                let str = NSAttributedString(
                    string: "\(new)",
                    attributes: numberAttrs(highlighted: isHovered, commented: hasLineComment(side: .new, lineNumber: new))
                )
                str.draw(in: NSRect(x: col2X, y: textY, width: columnWidth - 4, height: lineHeight))
            }

            drawPrefix(meta.kind, at: NSRect(x: prefixX, y: textY, width: Self.prefixColumnWidth, height: lineHeight))
            drawHoveredCommentBubble(for: meta, atY: y, x: totalWidth - 12)
        }
    }

    private func drawSingleColumnGutter(
        _ dirtyRect: NSRect,
        totalWidth: CGFloat,
        keyPath: KeyPath<DiffLineMetadata, Int?>
    ) {
        cachedBorderColor.setFill()
        NSRect(x: columnWidth, y: dirtyRect.origin.y, width: 1, height: dirtyRect.height).fill()

        for (index, meta) in lineMetadata.enumerated() {
            let y = CGFloat(index) * lineHeight
            guard dirtyRect.intersects(NSRect(x: 0, y: y, width: totalWidth, height: lineHeight)) else { continue }
            guard let num = meta[keyPath: keyPath] else { continue }
            let isHovered = hoveredCell == .single(lineIndex: index)
            let textY = y + (lineHeight - numberFont.ascender + numberFont.descender) / 2
            let side: DiffLineSide = mode == .singleOld ? .old : .new
            let str = NSAttributedString(
                string: "\(num)",
                attributes: numberAttrs(highlighted: isHovered, commented: hasLineComment(side: side, lineNumber: num))
            )
            str.draw(in: NSRect(x: 0, y: textY, width: columnWidth - 4, height: lineHeight))
            drawHoveredCommentBubble(for: meta, atY: y, x: totalWidth - 12)
        }
    }

    private func drawHoveredCommentBubble(for meta: DiffLineMetadata, atY y: CGFloat, x: CGFloat) {
        guard let comment = hoveredComment(for: meta) else { return }
        let text = comment.text as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        let maxWidth: CGFloat = 240
        let textRect = text.boundingRect(
            with: NSSize(width: maxWidth - 18, height: 80),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        let expandedWidth = min(max(textRect.width + 18, 52), maxWidth)
        let expandedHeight = min(max(textRect.height + 8, lineHeight - 4), 88)
        let progress = max(commentHoverProgress, 0.18)
        let width = 18 + (expandedWidth - 18) * progress
        let height = (lineHeight - 4) + (expandedHeight - (lineHeight - 4)) * progress
        let rect = NSRect(x: x + 4, y: y + 2, width: width, height: height)
        KajiTheme.nsBg.blended(withFraction: 0.18, of: cachedNumberHoverColor)?.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        if progress > 0.72 {
            text.draw(with: rect.insetBy(dx: 8, dy: 4), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
        }
    }

    private func animateCommentBubbleIfNeeded() {
        commentHoverProgress = 0
        needsDisplay = true
        guard let hoveredCell, let lineNumber = lineNumberForCell(hoveredCell), let side = sideForCell(hoveredCell), hasLineComment(
            side: side,
            lineNumber: lineNumber
        )
        else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            commentHoverProgress = 1
            animator().needsDisplay = true
        }
    }

    private func hoveredComment(for meta: DiffLineMetadata) -> DiffComment? {
        guard let hoveredCell else { return nil }
        return comments.first { comment in
            switch comment.anchor {
            case let .line(path, side, lineNumber):
                guard path == filePath else { return false }
                switch hoveredCell {
                case .old:
                    return side == .old && meta.oldLineNumber == lineNumber
                case .new:
                    return side == .new && meta.newLineNumber == lineNumber
                case .single:
                    return side == (mode == .singleOld ? .old : .new) &&
                        (side == .old ? meta.oldLineNumber == lineNumber : meta.newLineNumber == lineNumber)
                }
            case .file:
                return false
            }
        }
    }

    private func hasLineComment(side: DiffLineSide, lineNumber: Int) -> Bool {
        comments.contains { comment in
            if case let .line(path, commentSide, commentLineNumber) = comment.anchor {
                return path == filePath && commentSide == side && commentLineNumber == lineNumber
            }
            return false
        }
    }

    private func drawPrefix(_ kind: DiffDisplayRow.Kind, at rect: NSRect) {
        let (symbol, color): (String, NSColor?) = switch kind {
        case .addition: ("+", cachedAddColor)
        case .deletion: ("-", cachedRemoveColor)
        default: (" ", nil)
        }
        guard let color else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: prefixFont,
            .foregroundColor: color,
            .paragraphStyle: prefixParagraphStyle,
        ]
        NSAttributedString(string: symbol, attributes: attrs).draw(in: rect)
    }
}
