import AppKit
import Testing

@testable import Droid

struct WindowTrafficLightLayoutTests {
    @Test("legacy layout preserves only vertical offset")
    func legacyLayoutPreservesHorizontalPosition() {
        let frame = CGRect(x: 2, y: 20, width: 14, height: 14)
        let result = WindowTrafficLightLayout.frame(for: .closeButton, currentFrame: frame, isTahoe: false)

        #expect(result.origin.x == 2)
        #expect(result.origin.y == WindowTrafficLightLayout.legacyY)
    }

    @Test("Tahoe layout keeps traffic lights away from the extreme corner")
    func tahoeLayoutAddsLeftInsetAndSpacing() {
        let frame = CGRect(x: 0, y: 0, width: 14, height: 14)

        let close = WindowTrafficLightLayout.frame(for: .closeButton, currentFrame: frame, isTahoe: true)
        let minimize = WindowTrafficLightLayout.frame(for: .miniaturizeButton, currentFrame: frame, isTahoe: true)
        let zoom = WindowTrafficLightLayout.frame(for: .zoomButton, currentFrame: frame, isTahoe: true)

        #expect(close.origin.x == 14)
        #expect(minimize.origin.x == 36)
        #expect(zoom.origin.x == 58)
        #expect(close.origin.y == 9)
    }
}
