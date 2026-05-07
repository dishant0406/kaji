import AppKit

enum WindowTrafficLightLayout {
    static let legacyY: CGFloat = 3.5

    static func frame(for button: NSWindow.ButtonType, currentFrame: CGRect, isTahoe: Bool) -> CGRect {
        var frame = currentFrame
        guard isTahoe else {
            frame.origin.y = legacyY
            return frame
        }

        let titleBarHeight: CGFloat = 32
        let leftInset: CGFloat = 14
        let gap: CGFloat = 8
        frame.origin.x = leftInset + CGFloat(index(for: button)) * (frame.width + gap)
        frame.origin.y = max(7, (titleBarHeight - frame.height) / 2)
        return frame
    }

    private static func index(for button: NSWindow.ButtonType) -> Int {
        switch button {
        case .closeButton:
            0
        case .miniaturizeButton:
            1
        case .zoomButton:
            2
        default:
            0
        }
    }
}
