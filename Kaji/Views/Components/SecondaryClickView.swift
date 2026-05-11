import AppKit
import SwiftUI

struct SecondaryClickView: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> SecondaryClickNSView {
        let view = SecondaryClickNSView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: SecondaryClickNSView, context: Context) {
        nsView.action = action
    }
}

final class SecondaryClickNSView: NSView {
    var action: (() -> Void)?

    override func isAccessibilityElement() -> Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent else { return nil }
        if event.type == .rightMouseDown { return super.hitTest(point) }
        if event.type == .leftMouseDown, event.modifierFlags.contains(.control) {
            return super.hitTest(point)
        }
        return nil
    }

    override func rightMouseDown(with event: NSEvent) {
        action?()
    }

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.control) else {
            super.mouseDown(with: event)
            return
        }
        action?()
    }
}
