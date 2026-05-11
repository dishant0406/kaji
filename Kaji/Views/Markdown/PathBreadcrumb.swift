import SwiftUI

struct PathBreadcrumb: View {
    let path: String

    private var components: [String] {
        path.components(separatedBy: "/").filter { !$0.isEmpty }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                if index > 0 {
                    KajiIcon(systemName: "chevron.right", size: 7)
                        .foregroundStyle(KajiTheme.fgDim)
                }
                Text(component)
                    .kajiFont(size: 10)
                    .foregroundStyle(index == components.count - 1 ? KajiTheme.fg : KajiTheme.fgMuted)
                    .lineLimit(1)
            }
        }
    }
}
