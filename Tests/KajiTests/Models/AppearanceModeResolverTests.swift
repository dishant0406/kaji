import Testing

@testable import Kaji

struct AppearanceModeResolverTests {
    @Test
    func fallsBackToLegacyTransparencyWhenModeIsUnset() {
        let mode = AppearanceModeResolver.effectiveMode(
            modeRaw: "",
            legacyTransparencyEnabled: true,
            reduceTransparency: false
        )

        #expect(mode == .translucent)
    }

    @Test
    func reduceTransparencyForcesSolidMode() {
        let mode = AppearanceModeResolver.effectiveMode(
            modeRaw: AppearanceMode.translucent.rawValue,
            legacyTransparencyEnabled: true,
            reduceTransparency: true
        )

        #expect(mode == .solid)
    }

    @Test
    func glassRequestNeverFallsBackToSolidWhenTransparencyIsAllowed() {
        let mode = AppearanceModeResolver.effectiveMode(
            modeRaw: AppearanceMode.glass.rawValue,
            legacyTransparencyEnabled: false,
            reduceTransparency: false
        )

        #expect(mode == (AppearanceCapabilities.supportsLiquidGlass ? .glass : .translucent))
    }

    @Test
    func requestedGlassFallsBackToTranslucentWhenUnsupported() {
        let mode = AppearanceModeResolver.requestedMode(
            modeRaw: AppearanceMode.glass.rawValue,
            legacyTransparencyEnabled: false
        )

        #expect(mode == (AppearanceCapabilities.supportsLiquidGlass ? .glass : .translucent))
    }

    @Test
    func solidRequestRemainsSolidWhenTransparencyIsAllowed() {
        let mode = AppearanceModeResolver.effectiveMode(
            modeRaw: AppearanceMode.solid.rawValue,
            legacyTransparencyEnabled: true,
            reduceTransparency: false
        )

        #expect(mode == .solid)
    }
}
