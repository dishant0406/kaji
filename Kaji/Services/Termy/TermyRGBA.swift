import AppKit
import TermyKit

struct TermyRGBA: Equatable {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8

    init(r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init(_ color: TermyFfiColor) {
        self.init(r: color.r, g: color.g, b: color.b, a: color.a)
    }

    var nsColor: NSColor {
        NSColor(
            srgbRed: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
