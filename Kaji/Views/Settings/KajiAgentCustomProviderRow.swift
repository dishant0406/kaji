import SwiftUI

struct KajiAgentCustomProviderRow: View {
    let provider: KajiAgentCustomProvider
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(provider.id)
                        .kajiFont(size: 12, weight: .semibold, design: .monospaced)
                        .foregroundStyle(KajiTheme.fg)
                    Text(provider.api.title)
                        .kajiFont(size: 10, design: .monospaced)
                        .foregroundStyle(KajiTheme.fgDim)
                }
                Text(detail)
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button("Edit", action: onEdit)
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            Button("Delete", role: .destructive, action: onDelete)
                .buttonStyle(KajiButtonStyle(.ghost, size: .small))
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, 9)
        .background(KajiTheme.surface.opacity(0.36), in: RoundedRectangle(cornerRadius: KajiShape.panelRadius))
        .overlay(RoundedRectangle(cornerRadius: KajiShape.panelRadius).stroke(KajiTheme.border, lineWidth: 1))
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
    }

    private var detail: String {
        let discovery = provider.discovery == .none ? "manual" : provider.discovery.title
        let modelText = provider.modelCount == 1 ? "1 model" : "\(provider.modelCount) models"
        let auth = provider.auth == .none ? "no auth" : "API key"
        return "\(discovery) · \(modelText) · \(auth) · \(provider.baseUrl)"
    }
}
