import Foundation

enum AppearanceTransparencyStyle {
    static func clampedAmount(_ amount: Double) -> Double {
        min(max(amount, 0), 1)
    }

    static func adjustedTintOpacity(baseTintOpacity: Double, amount: Double) -> Double {
        let normalized = clampedAmount(amount)
        let maxTint = min(0.96, baseTintOpacity + 0.34)
        return maxTint - ((maxTint - baseTintOpacity) * normalized)
    }

    static func adjustedGradientOpacity(baseGradientOpacity: Double, amount: Double) -> Double {
        baseGradientOpacity * clampedAmount(amount)
    }

    static func sidebarTintOpacity(enabled: Bool, amount: Double) -> Double {
        enabled ? 0.46 - (0.22 * clampedAmount(amount)) : 1
    }

    static func sidebarGradientOpacity(enabled: Bool, amount: Double) -> Double {
        enabled ? 0.04 + (0.08 * clampedAmount(amount)) : 0
    }

    static func chromeTintOpacity(enabled: Bool, amount: Double) -> Double {
        enabled ? 0.54 - (0.22 * clampedAmount(amount)) : 1
    }
}
