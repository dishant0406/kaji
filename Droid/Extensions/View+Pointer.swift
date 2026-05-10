import AppKit
import SwiftUI

extension View {
    func droidPointer(_ cursor: NSCursor = .pointingHand) -> some View {
        modifier(DroidPointerModifier(cursor: cursor))
    }
}

private struct DroidPointerModifier: ViewModifier {
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
