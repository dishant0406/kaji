import SwiftUI

struct KajiModalOverlay<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            content()
                .padding(24)
                .transition(KajiMotion.modalTransition(reduceMotion: reduceMotion))
        }
        .background(KajiEscapeKeyMonitor(onEscape: onDismiss))
    }
}
