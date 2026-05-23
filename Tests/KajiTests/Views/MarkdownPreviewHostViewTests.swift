import Testing

@testable import Kaji

@MainActor
@Suite("MarkdownPreviewHostView")
struct MarkdownPreviewHostViewTests {
    @Test("keeps web view unhidden while waiting for first render")
    func keepsWebViewUnhiddenBeforeReveal() {
        let hostView = MarkdownPreviewHostView()
        let surface = MarkdownPreviewSurface()

        hostView.attach(surface: surface, visible: false)
        hostView.hide()

        #expect(surface.webView.isHidden == false)
        #expect(surface.webView.alphaValue == 0)
        surface.dispose()
    }

    @Test("advertises a nonzero intrinsic size for split panes")
    func hasNonzeroIntrinsicSize() {
        let hostView = MarkdownPreviewHostView()

        #expect(hostView.intrinsicContentSize.width >= 320)
        #expect(hostView.intrinsicContentSize.height > 0)
    }

    @Test("moving surface clears old host ownership without detaching new host")
    func movingSurfaceClearsOldHostOwnership() {
        let firstHost = MarkdownPreviewHostView()
        let secondHost = MarkdownPreviewHostView()
        let surface = MarkdownPreviewSurface()

        surface.attach(to: firstHost)
        surface.attach(to: secondHost)

        #expect(firstHost.surface == nil)
        #expect(secondHost.surface === surface)
        #expect(surface.webView.superview === secondHost)

        let detachedFromFirst = firstHost.detachSurface()

        #expect(detachedFromFirst == nil)
        #expect(secondHost.surface === surface)
        #expect(surface.webView.superview === secondHost)
        surface.dispose()
    }
}
