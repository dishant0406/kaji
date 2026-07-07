import Testing

@testable import Kaji

@Suite("Kaji spinner animation policy")
struct KajiSpinnerAnimationPolicyTests {
    @Test("battery optimized mode keeps spinner animated")
    func batteryOptimizedModeKeepsSpinnerAnimated() {
        #expect(KajiSpinnerAnimationPolicy.shouldAnimate(reduceMotion: false, batteryOptimized: true))
    }

    @Test("standard mode keeps spinner animated")
    func standardModeKeepsSpinnerAnimated() {
        #expect(KajiSpinnerAnimationPolicy.shouldAnimate(reduceMotion: false, batteryOptimized: false))
    }

    @Test("reduce motion disables spinner animation")
    func reduceMotionDisablesSpinnerAnimation() {
        #expect(!KajiSpinnerAnimationPolicy.shouldAnimate(reduceMotion: true, batteryOptimized: false))
        #expect(!KajiSpinnerAnimationPolicy.shouldAnimate(reduceMotion: true, batteryOptimized: true))
    }

    @Test("duration stays lightweight")
    func durationStaysLightweight() {
        #expect(KajiSpinnerAnimationPolicy.duration <= 1)
        #expect(KajiSpinnerAnimationPolicy.duration >= 0.5)
    }
}
