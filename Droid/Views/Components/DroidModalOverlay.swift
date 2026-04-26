import SwiftUI

struct DroidModalOverlay<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            content()
                .padding(24)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }
}
