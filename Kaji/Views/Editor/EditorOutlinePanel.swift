import SwiftUI

struct EditorOutlinePanel: View {
    let symbols: [EditorSymbol]
    let onSelect: (EditorSymbol) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Outline")
                    .kajiFont(size: 12, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                Spacer()
                Text("\(symbols.count)")
                    .kajiFont(size: 10)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider().overlay(KajiTheme.border)

            if symbols.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(symbols) { symbol in
                            Button {
                                onSelect(symbol)
                            } label: {
                                EditorOutlineRow(symbol: symbol)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 240)
        .background(KajiTheme.bg.opacity(0.94))
        .overlay(Rectangle().fill(KajiTheme.border).frame(width: 1), alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            KajiIcon(systemName: "list.bullet.rectangle", size: 18)
                .foregroundStyle(KajiTheme.fgMuted)
            Text("No symbols")
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct EditorOutlineRow: View {
    let symbol: EditorSymbol

    var body: some View {
        HStack(spacing: 8) {
            KajiIcon(systemName: icon, size: 10)
                .foregroundStyle(KajiTheme.fgMuted)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(symbol.name)
                    .kajiFont(size: 12, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                    .lineLimit(1)
                Text("Line \(symbol.line + 1)")
                    .kajiFont(size: 10)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
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
