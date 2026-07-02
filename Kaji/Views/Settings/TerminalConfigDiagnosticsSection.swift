import AppKit
import SwiftUI

struct TerminalConfigDiagnosticsSection: View {
    @State private var termy = TermyService.shared

    var body: some View {
        SettingsSection("Termy Config", footer: footer, showsDivider: false) {
            if termy.diagnostics.isEmpty {
                SettingsRow("Status") {
                    Text("Valid")
                        .kajiFont(size: SettingsMetrics.footnoteFontSize, weight: .medium)
                        .foregroundStyle(KajiTheme.diffAddFg)
                }
            } else {
                ForEach(termy.diagnostics) { diagnostic in
                    diagnosticRow(diagnostic)
                }
            }
            SettingsRow("Config file") {
                HStack(spacing: 8) {
                    Button("Open") {
                        NSWorkspace.shared.open(KajiConfig.shared.termyConfigURL)
                    }
                    .buttonStyle(KajiButtonStyle(.ghost, size: .small))
                    Button("Reload") {
                        termy.reloadConfig()
                        NotificationCenter.default.post(name: .themeDidChange, object: nil)
                    }
                    .buttonStyle(KajiButtonStyle(.primary, size: .small))
                }
            }
        }
    }

    private var footer: String {
        "Kaji preserves custom Termy config lines and validates the merged config before terminals reload."
    }

    private func diagnosticRow(_ diagnostic: TermyConfigDiagnostic) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("Line \(diagnostic.lineNumber)")
                    .kajiFont(size: SettingsMetrics.footnoteFontSize, weight: .semibold)
                    .foregroundStyle(KajiTheme.diffRemoveFg)
                Text(diagnostic.kind.label)
                    .kajiFont(size: SettingsMetrics.footnoteFontSize, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
            }
            Text(diagnostic.message)
                .kajiFont(size: SettingsMetrics.footnoteFontSize)
                .foregroundStyle(KajiTheme.fgDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
    }
}
