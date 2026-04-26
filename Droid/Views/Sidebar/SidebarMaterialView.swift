import AppKit
import SwiftUI

struct SidebarMaterialView: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    init(material: NSVisualEffectView.Material = .sidebar) {
        self.material = material
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = material
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.blendingMode = .behindWindow
        nsView.material = material
        nsView.state = .active
    }
}
