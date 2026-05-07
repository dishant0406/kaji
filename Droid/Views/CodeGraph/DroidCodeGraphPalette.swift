import SwiftUI

enum DroidCodeGraphPalette {
    @MainActor
    static func color(for community: Int?) -> Color {
        guard let community else { return DroidTheme.fgDim }
        return tokens[abs(community) % tokens.count]
    }

    @MainActor
    static func edge(selected: Bool) -> Color {
        selected ? DroidTheme.accent.opacity(0.78) : DroidTheme.fgDim.opacity(0.34)
    }

    @MainActor
    static func nodeStroke(selected: Bool) -> Color {
        selected ? DroidTheme.accent : DroidTheme.bg.opacity(0.78)
    }

    @MainActor
    static func label(selected: Bool) -> Color {
        selected ? DroidTheme.fg : DroidTheme.fgMuted
    }

    @MainActor
    private static var tokens: [Color] {
        [
            DroidTheme.accent,
            DroidTheme.diffAddFg,
            DroidTheme.diffHunkFg,
            DroidTheme.diffRemoveFg,
            DroidTheme.selection,
            DroidTheme.fgMuted,
            DroidTheme.accentSoft,
            DroidTheme.borderStrong,
        ]
    }
}
