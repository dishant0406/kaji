import SwiftUI

struct DroidCodeEditorField: View {
    @Binding var text: String
    let diagnostics: [DroidCodeDiagnostic]
    var placeholder = "#!/bin/zsh\nset -euo pipefail\n\n"
    var minHeight: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                DroidCodeEditor(text: $text, language: .shell, minHeight: minHeight)
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
            .background(DroidTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: DroidShape.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: DroidShape.controlRadius).stroke(borderColor, lineWidth: 1))

            ForEach(diagnostics) { diagnostic in
                HStack(alignment: .top, spacing: 6) {
                    DroidIcon(systemName: icon(for: diagnostic.severity), size: 10)
                        .foregroundStyle(color(for: diagnostic.severity))
                        .frame(width: 12, height: 14)
                    Text(message(for: diagnostic))
                        .droidFont(size: 11)
                        .foregroundStyle(color(for: diagnostic.severity))
                }
            }
        }
    }

    private var borderColor: Color {
        diagnostics.contains { $0.severity == .error } ? DroidTheme.diffRemoveFg.opacity(0.8) : DroidTheme.borderStrong.opacity(0.9)
    }

    private func message(for diagnostic: DroidCodeDiagnostic) -> String {
        guard let line = diagnostic.line else { return diagnostic.message }
        return "Line \(line): \(diagnostic.message)"
    }

    private func icon(for severity: DroidCodeDiagnosticSeverity) -> String {
        switch severity {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.circle"
        }
    }

    private func color(for severity: DroidCodeDiagnosticSeverity) -> Color {
        switch severity {
        case .info: DroidTheme.fgDim
        case .warning: DroidTheme.diffHunkFg
        case .error: DroidTheme.diffRemoveFg
        }
    }
}
