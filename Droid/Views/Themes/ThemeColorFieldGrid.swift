import SwiftUI

private enum ThemePaletteSlot {
    static let labels = [
        "Black",
        "Red",
        "Green",
        "Yellow",
        "Blue",
        "Magenta",
        "Cyan",
        "White",
        "Bright Black",
        "Bright Red",
        "Bright Green",
        "Bright Yellow",
        "Bright Blue",
        "Bright Magenta",
        "Bright Cyan",
        "Bright White",
    ]
}

struct ThemeColorFieldGrid: View {
    struct Row: Identifiable {
        let label: String
        let binding: Binding<String>
        let placeholder: String
        var monospaced = true
        var id: String { label }
    }

    let rows: [Row]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.label)
                        .droidFont(size: 11, weight: .medium)
                        .foregroundStyle(DroidTheme.fgMuted)
                    DroidInput(
                        placeholder: row.placeholder,
                        text: row.binding,
                        monospaced: row.monospaced
                    )
                }
            }
        }
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(minimum: 220), spacing: 12),
            GridItem(.flexible(minimum: 220), spacing: 12),
        ]
    }
}

struct ThemePaletteGrid: View {
    let colors: [Binding<String>]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0 ..< 8, id: \.self) { row in
                HStack(spacing: 12) {
                    paletteField(index: row)
                    paletteField(index: row + 8)
                }
            }
        }
    }

    private func paletteField(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ThemePaletteSlot.labels[index])
                .droidFont(size: 11, weight: .medium)
                .foregroundStyle(DroidTheme.fgMuted)
            DroidInput(
                placeholder: "#000000",
                text: colors[index],
                monospaced: true
            )
        }
        .frame(maxWidth: .infinity)
    }
}
