import SwiftUI

struct DroidSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var width: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = max(proxy.size.width, 1)
            let progress = progress(for: value)
            let thumbOffset = CGFloat(progress) * trackWidth

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DroidTheme.surface)
                    .frame(height: 4)

                Capsule()
                    .fill(DroidTheme.accent)
                    .frame(width: max(thumbOffset, 8), height: 4)

                Circle()
                    .fill(DroidTheme.fg)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(DroidTheme.borderStrong, lineWidth: 1))
                    .offset(x: min(max(thumbOffset - 6, 0), trackWidth - 12))
            }
            .frame(height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        updateValue(at: gesture.location.x, trackWidth: trackWidth)
                    }
            )
        }
        .frame(width: width, height: 18)
    }

    private func progress(for value: Double) -> Double {
        let normalized = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return min(max(normalized, 0), 1)
    }

    private func updateValue(at locationX: CGFloat, trackWidth: CGFloat) {
        let clampedX = min(max(locationX, 0), trackWidth)
        let normalized = clampedX / trackWidth
        value = range.lowerBound + Double(normalized) * (range.upperBound - range.lowerBound)
    }
}
