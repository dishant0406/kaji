import CoreGraphics
import Foundation

enum FooterTerminalSizing {
    static func height(from value: String, screenHeight: CGFloat?) -> CGFloat {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("%"),
           let percent = Double(trimmed.dropLast()),
           let screenHeight
        {
            return clamp(screenHeight * CGFloat(percent / 100))
        }
        if trimmed.hasSuffix("px"), let pixels = Double(trimmed.dropLast(2)) {
            return clamp(CGFloat(pixels))
        }
        if let pixels = Double(trimmed) {
            return clamp(CGFloat(pixels))
        }
        return 320
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 180), 720)
    }
}
