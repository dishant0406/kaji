import SwiftUI

struct CreateWorktreeFormSection<Content: View>: View {
    let title: String
    let detail: String?
    let showsDivider: Bool
    @ViewBuilder var content: Content

    init(
        _ title: String,
        detail: String? = nil,
        showsDivider: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.showsDivider = showsDivider
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .kajiFont(size: 11, weight: .semibold)
                        .foregroundStyle(KajiTheme.fgDim)
                    if let detail {
                        Text(detail)
                            .kajiFont(size: 11)
                            .foregroundStyle(KajiTheme.fgDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            if showsDivider {
                Rectangle()
                    .fill(KajiTheme.border)
                    .frame(height: 1)
                    .padding(.horizontal, 18)
            }
        }
    }
}

struct CreateWorktreeLabeledField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .kajiFont(size: 11, weight: .semibold)
                .foregroundStyle(KajiTheme.fgMuted)
            content
        }
    }
}
