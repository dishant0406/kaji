import AppKit
import CEFBridge
import SwiftUI

struct NativeBrowserSurface: NSViewRepresentable {
    let controller: BrowserWebController
    let page: BrowserPageState
    let projectPath: String
    let isActive: Bool
    let callbacks: BrowserSurfaceCallbacks

    func makeNSView(context _: Context) -> NativeBrowserSurfaceView {
        let view = NativeBrowserSurfaceView()
        controller.attach(
            surface: view,
            page: page,
            projectPath: projectPath,
            isActive: isActive,
            callbacks: callbacks
        )
        return view
    }

    func updateNSView(_ view: NativeBrowserSurfaceView, context _: Context) {
        controller.attach(
            surface: view,
            page: page,
            projectPath: projectPath,
            isActive: isActive,
            callbacks: callbacks
        )
    }
}

@MainActor
final class NativeBrowserSurfaceView: NSView {
    weak var controller: BrowserWebController?
    private var status = "Starting Chromium…"
    private weak var browserView: KajiCEFBrowserView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        browserView?.focusBrowser()
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        browserView?.focusBrowser()
        return true
    }

    func install(browserView: KajiCEFBrowserView) {
        guard self.browserView !== browserView || browserView.superview !== self else {
            browserView.frame = bounds
            return
        }
        self.browserView = browserView
        status = ""
        browserView.removeFromSuperview()
        browserView.frame = bounds
        browserView.autoresizingMask = [.width, .height]
        addSubview(browserView)
        needsDisplay = true
    }

    func contains(browserView: KajiCEFBrowserView) -> Bool {
        self.browserView === browserView && browserView.superview === self
    }

    func show(status: String) {
        self.status = status
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        browserView?.frame = bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !status.isEmpty else { return }
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        let text = NSAttributedString(string: status, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        text.draw(at: NSPoint(x: 16, y: max(16, bounds.height - 32)))
    }
}
