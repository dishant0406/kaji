import SwiftUI

struct KajiSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var width: CGFloat?
    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = max(proxy.size.width, 1)
            let progress = progress(for: value)
            let thumbOffset = CGFloat(progress) * trackWidth

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(KajiTheme.surface)
                    .frame(height: 4)

                Capsule()
                    .fill(KajiTheme.accent)
                    .frame(width: max(thumbOffset, 8), height: 4)

                Circle()
                    .fill(KajiTheme.fg)
                    .frame(width: isDragging ? 15 : 12, height: isDragging ? 15 : 12)
                    .overlay(Circle().stroke(KajiTheme.borderStrong, lineWidth: 1))
                    .offset(x: min(max(thumbOffset - (isDragging ? 7.5 : 6), 0), trackWidth - (isDragging ? 15 : 12)))
            }
            .frame(height: 18)
            .contentShape(Rectangle())
            .animation(KajiMotion.fast, value: value)
            .animation(KajiMotion.fast, value: isDragging)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        updateValue(at: gesture.location.x, trackWidth: trackWidth)
                    }
                    .onEnded { _ in isDragging = false }
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
