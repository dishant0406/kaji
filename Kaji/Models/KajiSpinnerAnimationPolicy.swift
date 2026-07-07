enum KajiSpinnerAnimationPolicy {
    static let duration = 0.85

    static func shouldAnimate(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    static func shouldAnimate(reduceMotion: Bool, batteryOptimized _: Bool) -> Bool {
        shouldAnimate(reduceMotion: reduceMotion)
    }
}
