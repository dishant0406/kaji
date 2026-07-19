import SwiftUI

struct SettingsSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var width: CGFloat = SettingsMetrics.controlWidth
    var valueWidth: CGFloat = 44
    var isEnabled = true
    var valueText: (Double) -> String

    var body: some View {
        SettingsRow(label) {
            HStack(spacing: 10) {
                KajiSlider(value: $value, range: range, width: width - valueWidth - 10)
                Text(valueText(value))
                    .kajiFont(size: SettingsMetrics.footnoteFontSize, weight: .medium)
                    .foregroundStyle(KajiTheme.fgDim)
                    .frame(width: valueWidth, alignment: .trailing)
            }
            .frame(width: width, alignment: .trailing)
            .opacity(isEnabled ? 1 : 0.45)
            .allowsHitTesting(isEnabled)
        }
    }
}
