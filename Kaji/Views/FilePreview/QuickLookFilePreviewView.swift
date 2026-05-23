import QuickLookUI
import SwiftUI

struct QuickLookFilePreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context _: Context) -> NSView {
        let container = NSView()
        guard let view = QLPreviewView(frame: .zero, style: .normal) else { return container }
        view.autostarts = true
        view.shouldCloseWithWindow = false
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateNSView(_ view: NSView, context _: Context) {
        guard let preview = view.subviews.compactMap({ $0 as? QLPreviewView }).first else { return }
        preview.previewItem = url as NSURL
    }
}
