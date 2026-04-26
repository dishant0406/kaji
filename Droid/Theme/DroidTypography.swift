import SwiftUI

private struct DroidFontModifier: ViewModifier {
    @Environment(AppTypographySettings.self) private var typography
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content
            .font(typography.uiFont(size: size, design: design))
            .fontWeight(weight)
    }
}

extension View {
    func droidFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(DroidFontModifier(size: size, weight: weight, design: design))
    }
}
