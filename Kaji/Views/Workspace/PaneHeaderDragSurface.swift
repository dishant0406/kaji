import AppKit
import SwiftUI

struct PaneHeaderDragSurface: NSViewRepresentable {
    let onChanged: (CGPoint) -> Void
    let onEnded: (CGPoint) -> Void

    func makeNSView(context _: Context) -> PaneHeaderDragSurfaceView {
        let view = PaneHeaderDragSurfaceView()
        view.onChanged = onChanged
        view.onEnded = onEnded
        return view
    }

    func updateNSView(_ view: PaneHeaderDragSurfaceView, context _: Context) {
        view.onChanged = onChanged
        view.onEnded = onEnded
    }
}

final class PaneHeaderDragSurfaceView: NSView {
    var onChanged: ((CGPoint) -> Void)?
    var onEnded: ((CGPoint) -> Void)?
    private var startPoint: CGPoint?
    private var isDragging = false

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: isDragging ? .closedHand : .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        startPoint = point(for: event)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let point = point(for: event)
        guard let startPoint else { return }
        if !isDragging {
            guard hypot(point.x - startPoint.x, point.y - startPoint.y) >= 3 else { return }
            isDragging = true
            window?.invalidateCursorRects(for: self)
        }
        onChanged?(point)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            startPoint = nil
            isDragging = false
            window?.invalidateCursorRects(for: self)
        }
        guard isDragging else { return }
        onEnded?(point(for: event))
    }

    private func point(for event: NSEvent) -> CGPoint {
        guard let contentView = window?.contentView else { return event.locationInWindow }
        let point = contentView.convert(event.locationInWindow, from: nil)
        guard !contentView.isFlipped else { return point }
        return CGPoint(x: point.x, y: contentView.bounds.height - point.y)
    }
}
