import AppKit
import SwiftUI

enum KajiCursor {
    case arrow
    case pointer
    case text
    case disabled
    case resizeLeftRight
    case resizeUpDown
    case openHand
    case closedHand

    var name: String {
        switch self {
        case .arrow: "arrow"
        case .pointer: "pointer"
        case .text: "text"
        case .disabled: "disabled"
        case .resizeLeftRight: "resizeLeftRight"
        case .resizeUpDown: "resizeUpDown"
        case .openHand: "openHand"
        case .closedHand: "closedHand"
        }
    }

    var nsCursor: NSCursor {
        switch self {
        case .arrow: .arrow
        case .pointer: .pointingHand
        case .text: .iBeam
        case .disabled: .operationNotAllowed
        case .resizeLeftRight: .resizeLeftRight
        case .resizeUpDown: .resizeUpDown
        case .openHand: .openHand
        case .closedHand: .closedHand
        }
    }
}

extension View {
    func kajiCursor(_ cursor: KajiCursor, isEnabled: Bool = true) -> some View {
        modifier(KajiCursorModifier(cursor: cursor.nsCursor, isEnabled: isEnabled))
    }

    func kajiPointer(_ cursor: NSCursor = .pointingHand) -> some View {
        modifier(KajiCursorModifier(cursor: cursor, isEnabled: true))
    }
}

private struct KajiCursorModifier: ViewModifier {
    let cursor: NSCursor
    let isEnabled: Bool
    @Environment(\.isEnabled) private var environmentIsEnabled

    func body(content: Content) -> some View {
        content
            .overlay {
                KajiCursorRegion(cursor: effectiveCursor)
                    .allowsHitTesting(false)
            }
    }

    private var effectiveCursor: NSCursor {
        isEnabled && environmentIsEnabled ? cursor : NSCursor.operationNotAllowed
    }
}

private struct KajiCursorRegion: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context _: Context) -> KajiCursorNSView {
        KajiCursorNSView(cursor: cursor)
    }

    func updateNSView(_ view: KajiCursorNSView, context _: Context) {
        view.cursor = cursor
    }
}

private final class KajiCursorNSView: NSView {
    var cursor: NSCursor {
        didSet { window?.invalidateCursorRects(for: self) }
    }

    init(cursor: NSCursor) {
        self.cursor = cursor
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}
