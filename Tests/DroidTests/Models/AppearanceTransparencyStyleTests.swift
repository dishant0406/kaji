import Testing

@testable import Droid

struct AppearanceTransparencyStyleTests {
    @Test
    func amountIsClamped() {
        #expect(AppearanceTransparencyStyle.clampedAmount(-1) == 0)
        #expect(AppearanceTransparencyStyle.clampedAmount(2) == 1)
    }

    @Test
    func adjustedTintBecomesMoreTransparentAtHigherValues() {
        let low = AppearanceTransparencyStyle.adjustedTintOpacity(baseTintOpacity: 0.46, amount: 0)
        let high = AppearanceTransparencyStyle.adjustedTintOpacity(baseTintOpacity: 0.46, amount: 1)

        #expect(low > high)
        #expect(high == 0.46)
    }

    @Test
    func disabledSurfacesStayOpaque() {
        #expect(AppearanceTransparencyStyle.sidebarTintOpacity(enabled: false, amount: 0.5) == 1)
        #expect(AppearanceTransparencyStyle.sidebarGradientOpacity(enabled: false, amount: 0.5) == 0)
        #expect(AppearanceTransparencyStyle.chromeTintOpacity(enabled: false, amount: 0.5) == 1)
    }
}
