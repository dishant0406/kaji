import SwiftUI

struct SpeechSettingsButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.borderless)
            .kajiFont(size: 12, weight: .medium)
            .foregroundStyle(KajiTheme.fg)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(KajiTheme.surface, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(KajiTheme.border, lineWidth: 1))
            .kajiPointer()
    }
}
