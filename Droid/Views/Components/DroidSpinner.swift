import SwiftUI

struct DroidSpinner: View {
    var size: CGFloat = 12
    var lineWidth: CGFloat = 1.6
    var color: Color = DroidTheme.fgMuted
    @State private var rotating = false

    var body: some View {
        Circle()
            .trim(from: 0.16, to: 0.82)
            .stroke(
                color,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                    rotating = true
                }
            }
    }
}
