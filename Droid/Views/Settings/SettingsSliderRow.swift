import SwiftUI

struct SettingsSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var width: CGFloat = SettingsMetrics.controlWidth
    var isEnabled = true
    var valueText: (Double) -> String

    var body: some View {
        SettingsRow(label) {
            HStack(spacing: 10) {
                DroidSlider(value: $value, range: range, width: width - 44)
                Text(valueText(value))
                    .droidFont(size: SettingsMetrics.footnoteFontSize, weight: .medium)
                    .foregroundStyle(DroidTheme.fgDim)
                    .frame(width: 34, alignment: .trailing)
            }
            .frame(width: width, alignment: .trailing)
            .opacity(isEnabled ? 1 : 0.45)
            .allowsHitTesting(isEnabled)
        }
    }
}
