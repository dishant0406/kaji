import AppKit
import CEFBridge
import SwiftUI

struct NativeBrowserSurface: NSViewRepresentable {
    let controller: BrowserWebController
    let page: BrowserPageState
    let projectPath: String
    let isActive: Bool
    let deviceProfile: BrowserDeviceProfile
    let callbacks: BrowserSurfaceCallbacks

    func makeNSView(context _: Context) -> NativeBrowserSurfaceView {
        let view = NativeBrowserSurfaceView()
        controller.attach(attachment(for: view))
        return view
    }

    func updateNSView(_ view: NativeBrowserSurfaceView, context _: Context) {
        controller.attach(attachment(for: view))
    }

    static func dismantleNSView(_ view: NativeBrowserSurfaceView, coordinator _: ()) {
        view.controller?.detach(surface: view)
    }

    private func attachment(for view: NativeBrowserSurfaceView) -> BrowserWebControllerAttachment {
        BrowserWebControllerAttachment(
            surface: view,
            page: page,
            projectPath: projectPath,
            isActive: isActive,
            deviceProfile: deviceProfile,
            callbacks: callbacks
        )
    }
}

@MainActor
final class NativeBrowserSurfaceView: NSView {
    private static let resizeEdgePassthrough: CGFloat = 28

    weak var controller: BrowserWebController?
    private var status = "Starting Chromium…"
    private weak var browserView: KajiCEFBrowserView?
    private var deviceProfile = BrowserDeviceProfiles.profile(for: BrowserDeviceProfiles.desktopID)

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

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isResizeEdge(point) {
            return nil
        }
        return super.hitTest(point)
    }

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
            browserView.frame = browserFrame
            return
        }
        self.browserView = browserView
        status = ""
        browserView.removeFromSuperview()
        browserView.frame = browserFrame
        browserView.autoresizingMask = []
        addSubview(browserView)
        needsDisplay = true
    }

    func release(controller: BrowserWebController, browserView: KajiCEFBrowserView?) {
        if self.controller === controller {
            self.controller = nil
        }
        guard let browserView else { return }
        uninstall(browserView: browserView)
    }

    func uninstall(browserView: KajiCEFBrowserView) {
        guard BrowserSurfaceAttachmentPolicy.shouldUninstallBrowserView(
            surfaceOwnsBrowserView: contains(browserView: browserView)
        )
        else { return }
        self.browserView = nil
        browserView.removeFromSuperview()
        needsDisplay = true
    }

    func applyDeviceProfile(_ profile: BrowserDeviceProfile) {
        deviceProfile = profile
        browserView?.frame = browserFrame
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
        browserView?.frame = browserFrame
    }

    private var browserFrame: NSRect {
        guard !deviceProfile.isDesktop else { return bounds }
        let width = min(CGFloat(deviceProfile.width), bounds.width)
        let x = max(0, (bounds.width - width) / 2)
        return NSRect(x: x, y: 0, width: width, height: bounds.height)
    }

    private func isResizeEdge(_ point: NSPoint) -> Bool {
        point.x <= Self.resizeEdgePassthrough ||
            bounds.maxX - point.x <= Self.resizeEdgePassthrough ||
            point.y <= Self.resizeEdgePassthrough ||
            bounds.maxY - point.y <= Self.resizeEdgePassthrough
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
