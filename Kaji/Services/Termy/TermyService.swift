import AppKit
import Foundation
import TermyKit

@MainActor @Observable
final class TermyService {
    static let shared = TermyService()

    private(set) var configVersion = 0
    private(set) var configContents = ""
    private var renderConfig = TermyRenderConfig.default

    private init() {
        reloadConfig()
    }

    var backgroundColor: NSColor { renderConfig.background.nsColor }
    var foregroundColor: NSColor { renderConfig.foreground.nsColor }
    var selectionBackgroundColor: NSColor { renderConfig.selectionBackground.nsColor }
    var accentColor: NSColor { renderConfig.cursor.nsColor }
    var currentRenderConfig: TermyRenderConfig { renderConfig }

    func paletteColor(at index: Int) -> NSColor? {
        index == 0 ? backgroundColor : nil
    }

    func reloadConfig() {
        configContents = KajiConfig.shared.readTermyConfig()
        renderConfig = TermyRenderConfig.load(contents: configContents)
        configVersion += 1
    }

    func shutdown() {}
}
