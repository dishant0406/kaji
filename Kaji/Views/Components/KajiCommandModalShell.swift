import SwiftUI

struct KajiCommandModalShell<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            KajiTheme.bg.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            content()
                .frame(width: width, height: height)
                .background(KajiTheme.bg)
                .clipShape(RoundedRectangle(cornerRadius: KajiShape.modalRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: KajiShape.modalRadius)
                        .stroke(KajiTheme.borderStrong.opacity(0.82), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityAddTraits(.isModal)
        }
    }
}
