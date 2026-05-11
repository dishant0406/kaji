import AppKit
import SwiftUI

struct SidePanelResizeHandle: NSViewRepresentable {
    let onDrag: (CGFloat) -> Void

    func makeNSView(context _: Context) -> SidePanelResizeHandleView {
        SidePanelResizeHandleView()
    }

    func updateNSView(_ view: SidePanelResizeHandleView, context _: Context) {
        view.onDrag = onDrag
        view.needsDisplay = true
    }
}

final class SidePanelResizeHandleView: NSView {
    var onDrag: ((CGFloat) -> Void)?
    private var dragStart: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragStart = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        onDrag?(point.x - dragStart.x)
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
    }
}
