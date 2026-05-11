import SwiftUI

enum KajiMotion {
    static let hover = Animation.easeOut(duration: 0.1)
    static let fast = Animation.easeOut(duration: 0.14)
    static let panel = Animation.interactiveSpring(response: 0.24, dampingFraction: 0.9, blendDuration: 0.04)
    static let modal = Animation.interactiveSpring(response: 0.28, dampingFraction: 0.88, blendDuration: 0.05)

    static func preferred(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.08) : animation
    }

    static func paneTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing))
    }

    static func modalTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985))
    }
}
