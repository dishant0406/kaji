import SwiftUI

struct NotificationFormRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .kajiFont(size: SettingsMetrics.footnoteFontSize, weight: .semibold)
                .foregroundStyle(KajiTheme.fgDim)
            content()
        }
    }
}

struct NotificationFormBlock<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .kajiFont(size: SettingsMetrics.footnoteFontSize, weight: .semibold)
                .foregroundStyle(KajiTheme.fgDim)
            content()
        }
    }
}
