import SwiftUI

struct HunkContextButton: View {
    let direction: DiffContextExpansionDirection
    let count: Int
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                KajiIcon(systemName: direction == .above ? "chevron.up" : "chevron.down", size: 9)
                    .frame(width: 22, height: 20)
                    .background(KajiTheme.bg, in: Capsule())
                    .overlay(Capsule().stroke(KajiTheme.border, lineWidth: 1))

                if isHovering {
                    Text(count.signum() == 1 ? "+20 (\(count))" : "+20")
                        .kajiFont(size: 10, weight: .semibold, design: .monospaced)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(KajiTheme.surface, in: Capsule())
                        .overlay(Capsule().stroke(KajiTheme.border, lineWidth: 1))
                        .offset(x: 24)
                        .fixedSize(horizontal: true, vertical: false)
                        .zIndex(2)
                }
            }
            .foregroundStyle(KajiTheme.accent)
            .frame(width: 22, height: 20, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(direction == .above ? "Show 20 lines above" : "Show 20 lines below")
        .onHover { isHovering = $0 }
        .kajiPointer()
    }
}
