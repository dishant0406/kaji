import SwiftUI

struct KajiCodeGraphZoomControls: View {
    let resetLabel: String
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            IconButton(symbol: "minus", accessibilityLabel: "Zoom Out", action: onZoomOut)
            IconButton(symbol: "plus", accessibilityLabel: "Zoom In", action: onZoomIn)
            IconButton(symbol: "arrow.counterclockwise", accessibilityLabel: resetLabel, action: onReset)
        }
        .padding(10)
    }
}
