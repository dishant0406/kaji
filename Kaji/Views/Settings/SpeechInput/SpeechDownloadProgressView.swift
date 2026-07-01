import SwiftUI

struct SpeechDownloadProgressView: View {
    let progress: SpeechDownloadProgress

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ProgressView(value: progress.clampedFraction)
                .progressViewStyle(.linear)
                .frame(width: 220)
            HStack(spacing: 6) {
                Text(progress.phaseTitle)
                Text(progress.percentTitle)
                    .foregroundStyle(KajiTheme.fgMuted)
            }
            .kajiFont(size: 11)
            .foregroundStyle(KajiTheme.fgDim)
        }
    }
}
