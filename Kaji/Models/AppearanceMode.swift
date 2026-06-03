import AppKit
import Foundation
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case solid = "Solid"
    case translucent = "Translucent"
    case glass = "Glass"

    var id: String { rawValue }
}

enum EffectiveAppearanceMode: Equatable {
    case solid
    case translucent
    case glass

    var usesTransparentWindow: Bool {
        switch self {
        case .solid:
            false
        case .translucent,
             .glass:
            true
        }
    }

    var usesSoftSurfaces: Bool {
        self != .solid
    }
}

enum AppearanceCapabilities {
    static var supportsLiquidGlass: Bool {
        #if compiler(>=6.2)
        guard #available(macOS 26.0, *) else { return false }
        return true
        #else
        return false
        #endif
    }
}

enum AppearanceModeResolver {
    static func requestedMode(modeRaw: String, legacyTransparencyEnabled: Bool) -> AppearanceMode {
        if let mode = AppearanceMode(rawValue: modeRaw), mode != .glass || AppearanceCapabilities.supportsLiquidGlass {
            return mode
        }
        if AppearanceMode(rawValue: modeRaw) == .glass {
            return .translucent
        }
        return legacyTransparencyEnabled ? .translucent : .solid
    }

    static func effectiveMode(
        modeRaw: String,
        legacyTransparencyEnabled: Bool,
        reduceTransparency: Bool
    ) -> EffectiveAppearanceMode {
        guard !reduceTransparency else { return .solid }
        switch requestedMode(modeRaw: modeRaw, legacyTransparencyEnabled: legacyTransparencyEnabled) {
        case .solid:
            return .solid
        case .translucent:
            return .translucent
        case .glass:
            return AppearanceCapabilities.supportsLiquidGlass ? .glass : .translucent
        }
    }

    static func effectiveModeForWindow(modeRaw: String, legacyTransparencyEnabled: Bool) -> EffectiveAppearanceMode {
        effectiveMode(
            modeRaw: modeRaw,
            legacyTransparencyEnabled: legacyTransparencyEnabled,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        )
    }
}

struct KajiAppearanceContext: Equatable {
    let effectiveMode: EffectiveAppearanceMode
    let transparencyAmount: Double

    static let solid = KajiAppearanceContext(effectiveMode: .solid, transparencyAmount: 0)
}

extension EnvironmentValues {
    @Entry var kajiAppearanceContext: KajiAppearanceContext = .solid
}

private struct KajiAppearanceContextModifier: ViewModifier {
    let modeRaw: String
    let legacyTransparencyEnabled: Bool
    let transparencyAmount: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.environment(
            \.kajiAppearanceContext,
            KajiAppearanceContext(
                effectiveMode: AppearanceModeResolver.effectiveMode(
                    modeRaw: modeRaw,
                    legacyTransparencyEnabled: legacyTransparencyEnabled,
                    reduceTransparency: reduceTransparency
                ),
                transparencyAmount: AppearanceTransparencyStyle.clampedAmount(transparencyAmount)
            )
        )
    }
}

extension View {
    func kajiAppearanceContext(
        modeRaw: String,
        legacyTransparencyEnabled: Bool,
        transparencyAmount: Double
    ) -> some View {
        modifier(KajiAppearanceContextModifier(
            modeRaw: modeRaw,
            legacyTransparencyEnabled: legacyTransparencyEnabled,
            transparencyAmount: transparencyAmount
        ))
    }
}
