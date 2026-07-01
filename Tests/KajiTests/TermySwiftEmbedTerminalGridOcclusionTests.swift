import AppKit
import XCTest
@testable import TermySwiftEmbed

@MainActor
final class TerminalGridOcclusionTests: XCTestCase {
    func testOcclusionDropsLayerBackingStoreAndRepaintsOnReturn() {
        let view = TerminalGridNSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.contentView = view
        XCTAssertNotNil(view.layer)

        // Stand in for the backing store the window server gives a drawn layer.
        view.layer?.contents = NSImage(size: NSSize(width: 1, height: 1))

        view.applyWindowOcclusion(visible: false)
        XCTAssertNil(view.layer?.contents, "occluded view must release its layer backing store")

        view.needsDisplay = false
        view.applyWindowOcclusion(visible: true)
        XCTAssertTrue(view.needsDisplay, "returning to visibility must schedule a repaint")
    }

    func testResizeDropsStaleLayerBackingStoreAndRepaints() {
        let view = TerminalGridNSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        XCTAssertNotNil(view.layer)
        view.layer?.contents = NSImage(size: NSSize(width: 1, height: 1))
        view.needsDisplay = false

        view.setFrameSize(NSSize(width: 240, height: 120))

        XCTAssertNil(view.layer?.contents, "resize must drop stale layer contents instead of stretching terminal art")
        XCTAssertTrue(view.layer?.needsDisplay() ?? false, "resize must schedule a layer repaint")
    }

    func testDrawClearsDirtyRectBeforeRendering() {
        var pixels = [UInt8](repeating: 255, count: 4 * 4 * 4)
        let context = CGContext(
            data: &pixels,
            width: 4,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let context else {
            XCTFail("Expected bitmap context")
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        TerminalGridNSView(frame: NSRect(x: 0, y: 0, width: 4, height: 4))
            .draw(NSRect(x: 0, y: 0, width: 4, height: 4))
        NSGraphicsContext.restoreGraphicsState()

        XCTAssertTrue(pixels.allSatisfy { $0 == 0 })
    }
}
