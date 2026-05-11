import SwiftUI

enum KajiCodeGraphPalette {
    @MainActor
    static func color(for community: Int?) -> Color {
        guard let community else { return KajiTheme.fgDim }
        return tokens[abs(community) % tokens.count]
    }

    @MainActor
    static func edge(selected: Bool) -> Color {
        selected ? KajiTheme.accent.opacity(0.78) : KajiTheme.fgDim.opacity(0.34)
    }

    @MainActor
    static func nodeStroke(selected: Bool) -> Color {
        selected ? KajiTheme.accent : KajiTheme.bg.opacity(0.78)
    }

    @MainActor
    static func label(selected: Bool) -> Color {
        selected ? KajiTheme.fg : KajiTheme.fgMuted
    }

    @MainActor
    private static var tokens: [Color] {
        [
            KajiTheme.accent,
            KajiTheme.diffAddFg,
            KajiTheme.diffHunkFg,
            KajiTheme.diffRemoveFg,
            KajiTheme.selection,
            KajiTheme.fgMuted,
            KajiTheme.accentSoft,
            KajiTheme.borderStrong,
        ]
    }
}
