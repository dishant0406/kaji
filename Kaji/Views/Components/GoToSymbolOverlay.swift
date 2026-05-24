import SwiftUI

struct GoToSymbolOverlay: View {
    let symbols: [EditorSymbol]
    let onSelect: (EditorSymbol) -> Void
    let onDismiss: () -> Void

    var body: some View {
        PaletteOverlay<EditorSymbol>(
            placeholder: "Type a symbol name",
            emptyLabel: "No symbols found",
            noMatchLabel: "No matching symbols",
            search: { query in
                Self.search(symbols: symbols, query: query)
            },
            onSelect: onSelect,
            onDismiss: onDismiss,
            row: { symbol, isHighlighted in
                AnyView(GoToSymbolRow(symbol: symbol, isHighlighted: isHighlighted))
            }
        )
    }

    private static func search(symbols: [EditorSymbol], query: String) -> [EditorSymbol] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return symbols }
        return symbols
            .map { symbol in (symbol, score(symbol.name.lowercased(), query: trimmed)) }
            .filter { $0.1 != nil }
            .sorted { ($0.1 ?? 0) > ($1.1 ?? 0) }
            .map(\.0)
    }

    private static func score(_ value: String, query: String) -> Int? {
        if value == query { return 1000 }
        if value.hasPrefix(query) { return 800 - value.count }
        if value.contains(query) { return 500 - value.count }
        var index = value.startIndex
        var score = 0
        for character in query {
            guard let found = value[index...].firstIndex(of: character) else { return nil }
            score += found == index ? 12 : 4
            index = value.index(after: found)
        }
        return score
    }
}

private struct GoToSymbolRow: View {
    let symbol: EditorSymbol
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            KajiIcon(systemName: icon, size: 12)
                .foregroundStyle(isHighlighted ? KajiTheme.fg : KajiTheme.fgMuted)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(symbol.name)
                    .kajiFont(size: 13, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                    .lineLimit(1)
                Text(symbol.kind.rawValue.capitalized)
                    .kajiFont(size: 10)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            Spacer(minLength: 12)
            Text("Line \(symbol.line + 1)")
                .kajiFont(size: 11, design: .monospaced)
                .foregroundStyle(isHighlighted ? KajiTheme.fgMuted : KajiTheme.fgDim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: KajiShape.panelRadius)
                .fill(isHighlighted ? KajiTheme.secondaryBackground : .clear)
        )
    }

    private var icon: String {
        switch symbol.kind {
        case .function: "function"
        case .type: "shippingbox"
        case .property: "tag"
        case .section: "textformat.size"
        }
    }
}
