import AppKit

final class KajiCodeLineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor(KajiTheme.secondaryBackground).setFill()
        rect.fill()
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        let visible = textView.enclosingScrollView?.contentView.bounds ?? textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let text = textView.string as NSString
        var line = lineNumber(at: glyphRange.location, text: text)
        var glyphIndex = glyphRange.location

        while glyphIndex < NSMaxRange(glyphRange) {
            var effectiveRange = NSRange()
            let rect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &effectiveRange,
                withoutAdditionalLayout: true
            )
            draw(line: line, y: rect.minY + textView.textContainerInset.height - visible.minY)
            glyphIndex = NSMaxRange(effectiveRange)
            line += 1
        }
    }

    private func draw(line: Int, y: CGFloat) {
        let string = "\(line)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(KajiTheme.fgDim),
        ]
        let size = string.size(withAttributes: attributes)
        string.draw(at: NSPoint(x: ruleThickness - size.width - 10, y: y), withAttributes: attributes)
    }

    private func lineNumber(at location: Int, text: NSString) -> Int {
        var line = 1
        var index = 0
        while index < min(location, text.length) {
            if text.character(at: index) == 10 { line += 1 }
            index += 1
        }
        return line
    }
}
