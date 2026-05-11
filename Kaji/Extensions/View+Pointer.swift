import AppKit
import SwiftUI

extension View {
    func kajiPointer(_ cursor: NSCursor = .pointingHand) -> some View {
        modifier(KajiPointerModifier(cursor: cursor))
    }
}

private struct KajiPointerModifier: ViewModifier {
    let cursor: NSCursor
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering {
                    cursor.push()
                    isHovering = true
                } else if isHovering {
                    NSCursor.pop()
                    isHovering = false
                }
            }
            .onDisappear {
                if isHovering {
                    NSCursor.pop()
                    isHovering = false
                }
            }
    }
}
