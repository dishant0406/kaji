import Foundation

struct ThemeDraft: Equatable {
    var name: String
    var slug: String
    var colors: ThemeColorSet

    static let droidDefaults = ThemeDraft(
        name: "",
        slug: "",
        colors: ThemeColorSet(
            background: "#0F1419",
            foreground: "#E6E1CF",
            cursorColor: "#E6B450",
            cursorText: "#0F1419",
            selectionBackground: "#273747",
            selectionForeground: "#E6E1CF",
            palette: [
                "#01060E", "#EA6C73", "#91B362", "#F9AF4F",
                "#53BDFA", "#FAE994", "#90E1C6", "#C7C7C7",
                "#686868", "#F07178", "#C2D94C", "#FFB454",
                "#59C2FF", "#FFEE99", "#95E6CB", "#FFFFFF",
            ]
        )
    )
}
