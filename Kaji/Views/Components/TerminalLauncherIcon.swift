import SwiftUI

struct TerminalLauncherIcon: View {
    let size: CGFloat
    var color: Color = KajiTheme.fgMuted

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let strokeWidth = max(1.25, width * 0.09)

            ZStack {
                RoundedRectangle(cornerRadius: width * 0.18, style: .continuous)
                    .stroke(color, lineWidth: strokeWidth)

                Path { path in
                    path.move(to: CGPoint(x: width * 0.24, y: height * 0.32))
                    path.addLine(to: CGPoint(x: width * 0.38, y: height * 0.5))
                    path.addLine(to: CGPoint(x: width * 0.24, y: height * 0.68))
                }
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
                )

                RoundedRectangle(cornerRadius: height * 0.06, style: .continuous)
                    .fill(color)
                    .frame(width: width * 0.22, height: max(1.5, height * 0.11))
                    .offset(x: width * 0.18, y: height * 0.18)
            }
        }
        .frame(width: size, height: size)
    }
}
