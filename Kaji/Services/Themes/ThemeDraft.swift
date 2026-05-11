import Foundation

struct ThemeDraft: Equatable {
    var name: String
    var slug: String
    var colors: ThemeColorSet

    static let kajiDefaults = ThemeDraft(
        name: "",
        slug: "",
        colors: ThemeColorSet(
            background: "#101010",
            foreground: "#FFFFFF",
            cursorColor: "#FFC799",
            cursorText: "#101010",
            selectionBackground: "#2D2D2D",
            selectionForeground: "#FFFFFF",
            palette: [
                "#242424", "#E07070", "#73C990", "#FFC799",
                "#688DFF", "#CF68FF", "#3FDEBE", "#BBBBBB",
                "#555555", "#FF8080", "#A8FF78", "#FFD9B3",
                "#9BB2F0", "#E8A1FF", "#7FFFD4", "#FFFFFF",
            ]
        )
    )
}
