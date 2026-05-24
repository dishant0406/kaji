import SwiftUI

struct MarkdownPreviewRepresentable: NSViewRepresentable {
    let identity: String
    let payload: MarkdownPreviewPayload
    let scrollRequestVersion: Int
    let scrollRequest: CGFloat?
    let onMetrics: (MarkdownPreviewMetrics) -> Void
    let onScroll: (CGFloat) -> Void
    let onReady: () -> Void
    let onLink: (MarkdownPreviewLinkRequest) -> Void

    func makeNSView(context: Context) -> MarkdownPreviewHostView {
        let hostView = MarkdownPreviewHostView()
        installSurface(in: hostView)
        return hostView
    }

    func updateNSView(_ hostView: MarkdownPreviewHostView, context: Context) {
        if hostView.surface?.ownerID != identity {
            hostView.detachSurface().map { surface in
                surface.detach(from: hostView)
                if let ownerID = surface.ownerID {
                    MarkdownPreviewSurfaceRegistry.shared.release(ownerID: ownerID)
                }
            }
            installSurface(in: hostView)
        }
        hostView.surface?.update(
            payload: payload,
            scrollRequestVersion: scrollRequestVersion,
            scrollRequest: scrollRequest,
            callbacks: callbacks
        )
    }

    static func dismantleNSView(_ hostView: MarkdownPreviewHostView, coordinator: ()) {
        guard let surface = hostView.detachSurface() else { return }
        surface.detach(from: hostView)
        guard let ownerID = surface.ownerID else { return }
        MarkdownPreviewSurfaceRegistry.shared.release(ownerID: ownerID)
    }

    private func installSurface(in hostView: MarkdownPreviewHostView) {
        let surface = MarkdownPreviewSurfaceRegistry.shared.surface(ownerID: identity)
        surface.attach(to: hostView)
        surface.update(
            payload: payload,
            scrollRequestVersion: scrollRequestVersion,
            scrollRequest: scrollRequest,
            callbacks: callbacks
        )
    }

    private var callbacks: MarkdownPreviewCallbacks {
        MarkdownPreviewCallbacks(onMetrics: onMetrics, onScroll: onScroll, onReady: onReady, onLink: onLink)
    }
}
