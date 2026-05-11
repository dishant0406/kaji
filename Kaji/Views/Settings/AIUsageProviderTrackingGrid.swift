import SwiftUI

struct AIUsageProviderTrackingGrid: View {
    let providers: [AIUsageProviderCatalogEntry]
    let bindingForProvider: (AIUsageProviderCatalogEntry) -> Binding<Bool>

    private let columns = [
        GridItem(.flexible(minimum: 140), spacing: 12),
        GridItem(.flexible(minimum: 140), spacing: 12),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(providers) { provider in
                AIUsageProviderTrackingCard(
                    provider: provider,
                    isOn: bindingForProvider(provider)
                )
            }
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, 10)
    }
}

private struct AIUsageProviderTrackingCard: View {
    let provider: AIUsageProviderCatalogEntry
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            ProviderIconView(iconName: provider.iconName, size: 16, style: .monochrome(KajiTheme.fg))

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .kajiFont(size: 12)
                    .foregroundStyle(KajiTheme.fg)
                    .lineLimit(1)

                if provider.hasNotificationIntegration {
                    Text("Integrated")
                        .kajiFont(size: 9, weight: .semibold)
                        .foregroundStyle(KajiTheme.fgDim)
                }
            }

            Spacer(minLength: 0)

            KajiSwitch(isOn: $isOn)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(KajiTheme.surface, in: RoundedRectangle(cornerRadius: KajiShape.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: KajiShape.panelRadius)
                .stroke(KajiTheme.border, lineWidth: 1)
        )
    }
}
