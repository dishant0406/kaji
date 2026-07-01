import SwiftUI

struct SpeechModelCatalogSection: View {
    let models: [SpeechInputModel]
    let selectedID: String
    let status: SpeechInputStatus
    let refreshToken: Int
    let onSelect: (String) -> Void
    let onDownload: (SpeechInputModel) -> Void
    let onPrepare: (SpeechInputModel) -> Void
    let onRemove: (SpeechInputModel) -> Void
    let onOpenJSON: () -> Void
    let onReload: () -> Void
    let registryError: String?

    var body: some View {
        SettingsSection(
            "Models",
            footer: "Add compatible FluidAudio models by editing the JSON registry. A model must use a runtime engine Kaji supports."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(models) { model in
                    SpeechModelCard(
                        model: model,
                        isSelected: selectedID == model.id,
                        cacheState: cacheState(model),
                        actionsEnabled: status.allowsModelActions,
                        onSelect: { onSelect(model.id) },
                        onDownload: { onDownload(model) },
                        onPrepare: { onPrepare(model) },
                        onRemove: { onRemove(model) }
                    )
                }
                registryActions
                if let registryError { registryWarning(registryError) }
            }
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            .padding(.vertical, 8)
        }
    }

    private var registryActions: some View {
        HStack(spacing: 8) {
            Text("Registry")
                .kajiFont(size: 11, weight: .medium)
                .foregroundStyle(KajiTheme.fgDim)
            Spacer(minLength: 0)
            SpeechSettingsButton("Open JSON", action: onOpenJSON)
            SpeechSettingsButton("Reload", action: onReload)
                .disabled(!status.allowsModelActions)
        }
    }

    private func registryWarning(_ text: String) -> some View {
        HStack(spacing: 7) {
            KajiIcon(systemName: "exclamationmark.triangle", size: 11)
                .foregroundStyle(KajiTheme.diffRemoveFg)
            Text(text)
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.diffRemoveFg)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(KajiTheme.diffRemoveBg.opacity(0.16), in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
    }

    private func cacheState(_ model: SpeechInputModel) -> SpeechModelCacheState {
        _ = refreshToken
        return model.cacheState
    }
}
