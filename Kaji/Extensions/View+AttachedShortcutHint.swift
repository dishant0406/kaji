import SwiftUI

enum AttachedShortcutHintPlacement {
    case topTrailing
    case topLeading
    case center
    case bottomTrailing
    case bottomLeading

    var alignment: Alignment {
        switch self {
        case .topTrailing: .topTrailing
        case .topLeading: .topLeading
        case .center: .center
        case .bottomTrailing: .bottomTrailing
        case .bottomLeading: .bottomLeading
        }
    }

    var offset: CGSize {
        switch self {
        case .topTrailing: CGSize(width: -4, height: 4)
        case .topLeading: CGSize(width: 4, height: 4)
        case .center: .zero
        case .bottomTrailing: CGSize(width: -4, height: -4)
        case .bottomLeading: CGSize(width: 4, height: -4)
        }
    }
}

extension View {
    func attachedShortcutHint(
        for action: ShortcutAction,
        placement: AttachedShortcutHintPlacement = .center,
        compact: Bool = true
    ) -> some View {
        modifier(ActionAttachedShortcutHintModifier(action: action, placement: placement, compact: compact))
    }

    func attachedShortcutHint(
        label: String,
        modifiers: UInt,
        placement: AttachedShortcutHintPlacement = .center,
        compact: Bool = true,
        showWhenAnyModifierHeld: Bool = false
    ) -> some View {
        modifier(AttachedShortcutHintModifier(
            label: label,
            modifiers: modifiers,
            placement: placement,
            compact: compact,
            showWhenAnyModifierHeld: showWhenAnyModifierHeld
        ))
    }
}

private struct ActionAttachedShortcutHintModifier: ViewModifier {
    let action: ShortcutAction
    let placement: AttachedShortcutHintPlacement
    let compact: Bool
    @State private var keyBindings = KeyBindingStore.shared

    func body(content: Content) -> some View {
        if let combo = keyBindings.assignedCombo(for: action) {
            content.attachedShortcutHint(
                label: combo.displayString,
                modifiers: combo.modifiers,
                placement: placement,
                compact: compact
            )
        } else {
            content
        }
    }
}

private struct AttachedShortcutHintModifier: ViewModifier {
    let label: String
    let modifiers: UInt
    let placement: AttachedShortcutHintPlacement
    let compact: Bool
    let showWhenAnyModifierHeld: Bool
    @State private var modifierKeys = ModifierKeyMonitor.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: placement.alignment) {
            if isVisible {
                ShortcutBadge(label: label, compact: compact)
                    .offset(placement.offset)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.94).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .animation(KajiMotion.preferred(KajiMotion.fast, reduceMotion: reduceMotion), value: isVisible)
    }

    private var isVisible: Bool {
        guard modifierKeys.showHints else { return false }
        if modifiers == 0 {
            return showWhenAnyModifierHeld
        }
        return modifierKeys.isHolding(modifiers: modifiers)
    }
}
