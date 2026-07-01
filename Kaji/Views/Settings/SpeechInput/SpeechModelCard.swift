import SwiftUI

struct SpeechModelCard: View {
    let model: SpeechInputModel
    let isSelected: Bool
    let cacheState: SpeechModelCacheState
    let actionsEnabled: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onPrepare: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Text(model.detail)
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
            SpeechModelBadgeRow(model: model)
            SpeechModelProsConsView(model: model)
            footer
        }
        .padding(10)
        .background(KajiTheme.surface.opacity(isSelected ? 0.92 : 0.54), in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .overlay(border)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(model.title)
                .kajiFont(size: 12, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            if isSelected {
                SpeechModelPill(title: "Selected", color: KajiTheme.accent)
            }
            Spacer(minLength: 0)
            Text(model.downloadSizeTitle)
                .kajiFont(size: 11, weight: .medium)
                .foregroundStyle(KajiTheme.fgDim)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            cacheIndicator
            Text(model.exactDownloadSizeTitle)
                .kajiFont(size: 10)
                .foregroundStyle(KajiTheme.fgDim)
                .lineLimit(1)
            Spacer(minLength: 0)
            if !isSelected {
                SpeechSettingsButton("Select", action: onSelect)
                    .disabled(!actionsEnabled)
            }
            SpeechSettingsButton("Download", action: onDownload)
                .disabled(!actionsEnabled || cacheState == .ready)
            SpeechSettingsButton("Prepare", action: onPrepare)
                .disabled(!actionsEnabled || cacheState != .ready)
            SpeechSettingsButton("Remove", action: onRemove)
                .disabled(!actionsEnabled || cacheState == .missing)
        }
    }

    private var cacheIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(cacheState.statusColorIsReady ? KajiTheme.diffAddFg : KajiTheme.fgDim)
                .frame(width: 7, height: 7)
            Text(cacheState.title)
                .kajiFont(size: 11, weight: .medium)
                .foregroundStyle(KajiTheme.fgMuted)
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: KajiShape.tileRadius)
            .strokeBorder(isSelected ? KajiTheme.accent.opacity(0.55) : KajiTheme.border, lineWidth: 1)
    }
}
