import Foundation

struct ThemeColorSet: Equatable, Sendable {
    var background: String
    var foreground: String
    var cursorColor: String
    var cursorText: String
    var selectionBackground: String
    var selectionForeground: String
    var palette: [String]

    init(
        background: String,
        foreground: String,
        cursorColor: String,
        cursorText: String,
        selectionBackground: String,
        selectionForeground: String,
        palette: [String]
    ) {
        self.background = background
        self.foreground = foreground
        self.cursorColor = cursorColor
        self.cursorText = cursorText
        self.selectionBackground = selectionBackground
        self.selectionForeground = selectionForeground
        self.palette = palette
    }
}
