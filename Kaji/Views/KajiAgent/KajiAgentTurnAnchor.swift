import AppKit
import SwiftUI

struct KajiAgentTurnAnchor: NSViewRepresentable {
    let id: UUID

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        view.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
    }
}
