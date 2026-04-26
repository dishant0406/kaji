import SwiftUI

struct DroidLinearProgressBar: View {
    var value: Double
    var total: Double = 100
    var height: CGFloat = 5
    var fill: Color = DroidTheme.accent
    var track: Color = DroidTheme.hover

    var body: some View {
        GeometryReader { proxy in
            let progress = max(0, min(1, total > 0 ? value / total : 0))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: min(height / 2, DroidShape.badgeRadius))
                    .fill(track)

                RoundedRectangle(cornerRadius: min(height / 2, DroidShape.badgeRadius))
                    .fill(fill)
                    .frame(width: max(height, proxy.size.width * progress))
            }
        }
        .frame(height: height)
        .accessibilityValue("\(Int((max(0, min(1, total > 0 ? value / total : 0)) * 100).rounded())) percent")
    }
}
