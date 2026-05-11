import SwiftUI

struct ThemeFormSection<Content: View>: View {
    let title: String
    let showsDivider: Bool
    @ViewBuilder let content: () -> Content

    init(_ title: String, showsDivider: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.showsDivider = showsDivider
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .kajiFont(size: 11, weight: .semibold)
                .foregroundStyle(KajiTheme.fgDim)
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 8)
            content()
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            if showsDivider {
                Rectangle()
                    .fill(KajiTheme.border)
                    .frame(height: 1)
                    .padding(.horizontal, 18)
            }
        }
    }
}
