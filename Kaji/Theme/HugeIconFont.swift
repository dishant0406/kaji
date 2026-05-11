import CoreText
import SwiftUI

@MainActor
enum HugeIconFont {
    private static let fileName = "hgi-stroke-rounded"
    private static let fontName = "hgi-stroke-rounded"
    private static var didRegister = false

    static func font(size: CGFloat) -> Font {
        registerIfNeeded()
        return .custom(fontName, size: size)
    }

    static func registerIfNeeded() {
        guard !didRegister else { return }
        guard let url = Bundle.hugeIconResourceURL(forResource: fileName, withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        didRegister = true
    }
}
