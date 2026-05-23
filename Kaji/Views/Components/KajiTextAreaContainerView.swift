import AppKit

final class KajiTextAreaContainerView: NSView {
    let scrollView = NSScrollView()
    let textView = KajiTextAreaNSTextView()
    let placeholder = NSTextField(labelWithString: "")
    private let contentInset = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]
        placeholder.backgroundColor = .clear
        placeholder.isBordered = false
        placeholder.isEditable = false
        placeholder.isEnabled = false
        placeholder.isSelectable = false
        addSubview(scrollView)
        addSubview(placeholder)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        let contentRect = NSRect(
            x: bounds.minX + contentInset.left,
            y: bounds.minY + contentInset.bottom,
            width: max(0, bounds.width - contentInset.left - contentInset.right),
            height: max(0, bounds.height - contentInset.top - contentInset.bottom)
        )
        scrollView.frame = contentRect
        textView.textContainer?.containerSize = NSSize(width: contentRect.width, height: .greatestFiniteMagnitude)
        let documentHeight = max(contentRect.height, usedTextHeight())
        textView.frame = NSRect(origin: .zero, size: NSSize(width: contentRect.width, height: documentHeight))
        let lineHeight = ceil(textView.font?.boundingRectForFont.height ?? 16)
        placeholder.frame = NSRect(
            x: contentRect.minX,
            y: contentRect.maxY - lineHeight,
            width: contentRect.width,
            height: lineHeight
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === placeholder ? textView : hit
    }

    func focusTextView() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard window?.firstResponder !== textView else { return }
            window?.makeFirstResponder(textView)
        }
    }

    private func usedTextHeight() -> CGFloat {
        guard let textContainer = textView.textContainer else { return 0 }
        textView.layoutManager?.ensureLayout(for: textContainer)
        let usedRect = textView.layoutManager?.usedRect(for: textContainer) ?? .zero
        return ceil(usedRect.height)
    }
}
