import SwiftUI

struct AIGatewayAdvancedSection<Content: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content

    var body: some View {
        SettingsSection("Advanced", showsDivider: !isExpanded) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(isExpanded ? "Hide advanced settings" : "Show advanced settings")
                        .kajiFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                        .foregroundStyle(KajiTheme.fg)
                    Spacer(minLength: 0)
                    KajiIcon(systemName: isExpanded ? "chevron.up" : "chevron.down", size: 10)
                        .foregroundStyle(KajiTheme.fgDim)
                }
                .padding(.horizontal, SettingsMetrics.horizontalPadding)
                .padding(.vertical, SettingsMetrics.rowVerticalPadding + 4)
            }
            .buttonStyle(.plain)
            .kajiPointer()
        }
        if isExpanded {
            content
        }
    }
}
