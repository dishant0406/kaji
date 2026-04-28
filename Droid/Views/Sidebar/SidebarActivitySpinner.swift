import SwiftUI

struct SidebarActivitySpinner: View {
    @State private var rotating = false

    var body: some View {
        Circle()
            .trim(from: 0.16, to: 0.82)
            .stroke(DroidTheme.accent, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            .frame(width: 10, height: 10)
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .onAppear {
                guard !rotating else { return }
                withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                    rotating = true
                }
            }
    }
}
