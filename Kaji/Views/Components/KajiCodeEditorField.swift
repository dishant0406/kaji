import SwiftUI

struct KajiCodeEditorField: View {
    @Binding var text: String
    let diagnostics: [KajiCodeDiagnostic]
    var placeholder = "#!/bin/zsh\nset -euo pipefail\n\n"
    var minHeight: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                KajiCodeEditor(text: $text, language: .shell, minHeight: minHeight)
                    .frame(minHeight: minHeight)
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color(nsColor: GhosttyService.shared.foregroundColor.withAlphaComponent(0.58)))
                        .padding(.leading, 56)
                        .padding(.top, 10)
                        .allowsHitTesting(false)
                }
            }
            .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: KajiShape.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: KajiShape.controlRadius).stroke(borderColor, lineWidth: 1))

            ForEach(diagnostics) { diagnostic in
                HStack(alignment: .top, spacing: 6) {
                    KajiIcon(systemName: icon(for: diagnostic.severity), size: 10)
                        .foregroundStyle(color(for: diagnostic.severity))
                        .frame(width: 12, height: 14)
                    Text(message(for: diagnostic))
                        .kajiFont(size: 11)
                        .foregroundStyle(color(for: diagnostic.severity))
                }
            }
        }
    }

    private var borderColor: Color {
        diagnostics.contains { $0.severity == .error } ? KajiTheme.diffRemoveFg.opacity(0.8) : KajiTheme.borderStrong.opacity(0.9)
    }

    private func message(for diagnostic: KajiCodeDiagnostic) -> String {
        guard let line = diagnostic.line else { return diagnostic.message }
        return "Line \(line): \(diagnostic.message)"
    }

    private func icon(for severity: KajiCodeDiagnosticSeverity) -> String {
        switch severity {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.circle"
        }
    }

    private func color(for severity: KajiCodeDiagnosticSeverity) -> Color {
        switch severity {
        case .info: KajiTheme.fgDim
        case .warning: KajiTheme.diffHunkFg
        case .error: KajiTheme.diffRemoveFg
        }
    }
}
