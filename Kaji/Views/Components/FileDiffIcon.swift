import SwiftUI

struct FileDiffIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / 24
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }

        var path = Path()
        path.move(to: point(12, 4))
        path.addLine(to: point(12, 20))
        path.move(to: point(7, 9))
        path.addLine(to: point(12, 4))
        path.addLine(to: point(17, 9))
        path.move(to: point(7, 15))
        path.addLine(to: point(12, 20))
        path.addLine(to: point(17, 15))
        return path
    }
}

struct FileDiffIconButton: View {
    let action: () -> Void

    var body: some View {
        IconButton(
            symbol: "arrow.triangle.branch",
            size: 13,
            accessibilityLabel: "Source Control"
        ) {
            action()
        }
    }
}
