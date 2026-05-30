import Pow
import SwiftUI

enum KajiMotion {
    static let hover = Animation.easeOut(duration: 0.1)
    static let fast = Animation.easeOut(duration: 0.14)
    static let panel = Animation.interactiveSpring(response: 0.24, dampingFraction: 0.9, blendDuration: 0.04)
    static let modal = Animation.interactiveSpring(response: 0.28, dampingFraction: 0.88, blendDuration: 0.05)
    static let press = Animation.interactiveSpring(response: 0.16, dampingFraction: 0.78, blendDuration: 0.02)
    static let select = Animation.interactiveSpring(response: 0.22, dampingFraction: 0.82, blendDuration: 0.03)

    static func preferred(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.08) : animation
    }

    static func paneTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .movingParts.blur.combined(with: .move(edge: .trailing))
    }

    static func modalTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .movingParts.blur.combined(with: .scale(scale: 0.985))
    }

    static func overlayTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .movingParts.blur.combined(with: .scale(scale: 0.982))
    }

    static func disclosureTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .movingParts.blur.combined(with: .move(edge: .top))
    }

    static func sidePanelTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)
    }

    static func bottomPanelTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    static func contentSwitchTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .movingParts.blur.combined(with: .scale(scale: 0.992))
    }

    static var tapFeedback: AnyChangeEffect { .jump(height: 2) }
    static var selectionFeedback: AnyChangeEffect { .shine(duration: 0.42) }
    static var successFeedback: AnyChangeEffect { .shine(duration: 0.55) }
    static var attentionFeedback: AnyChangeEffect { .pulse(shape: RoundedRectangle(cornerRadius: KajiShape.tileRadius), count: 1) }
    static var invalidFeedback: AnyChangeEffect { .shake(rate: .fast) }
}

struct KajiPressEffect: ViewModifier {
    let isPressed: Bool
    let isEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && isEnabled && !reduceMotion ? 0.965 : 1)
            .animation(KajiMotion.preferred(KajiMotion.press, reduceMotion: reduceMotion), value: isPressed)
    }
}

struct KajiHoverEffect: ViewModifier {
    let isActive: Bool
    let scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive && !reduceMotion ? scale : 1)
            .animation(KajiMotion.preferred(KajiMotion.hover, reduceMotion: reduceMotion), value: isActive)
    }
}

struct KajiChangeFeedback<Value: Equatable>: ViewModifier {
    let value: Value
    let effect: AnyChangeEffect
    let isEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.changeEffect(effect, value: value, isEnabled: isEnabled && !reduceMotion)
    }
}

extension View {
    func kajiPressEffect(isPressed: Bool, isEnabled: Bool = true) -> some View {
        modifier(KajiPressEffect(isPressed: isPressed, isEnabled: isEnabled))
    }

    func kajiHoverEffect(isActive: Bool, scale: CGFloat = 1.025) -> some View {
        modifier(KajiHoverEffect(isActive: isActive, scale: scale))
    }

    func kajiChangeFeedback<Value: Equatable>(
        _ effect: AnyChangeEffect,
        value: Value,
        isEnabled: Bool = true
    ) -> some View {
        modifier(KajiChangeFeedback(value: value, effect: effect, isEnabled: isEnabled))
    }
}
