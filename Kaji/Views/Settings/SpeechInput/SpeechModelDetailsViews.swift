import SwiftUI

struct SpeechModelBadgeRow: View {
    let model: SpeechInputModel

    var body: some View {
        HStack(spacing: 6) {
            SpeechModelPill(title: model.displayMode.title, color: KajiTheme.accent)
            SpeechModelPill(title: model.displayLanguageSummary, color: KajiTheme.fgMuted)
            ForEach((model.badges ?? []).filter { $0 != model.displayMode.title }, id: \.self) { badge in
                SpeechModelPill(title: badge, color: KajiTheme.fgMuted)
            }
        }
        .lineLimit(1)
    }
}

struct SpeechModelPill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .kajiFont(size: 10, weight: .semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(color.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 1))
    }
}

struct SpeechModelProsConsView: View {
    let model: SpeechInputModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SpeechModelBulletList(title: "Pros", color: KajiTheme.diffAddFg, items: model.pros ?? [])
            SpeechModelBulletList(title: "Cons", color: KajiTheme.diffRemoveFg, items: model.cons ?? [])
        }
    }
}

struct SpeechModelBulletList: View {
    let title: String
    let color: Color
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .kajiFont(size: 10, weight: .semibold)
                .foregroundStyle(color)
            ForEach(items.prefix(3), id: \.self) { item in
                HStack(alignment: .top, spacing: 5) {
                    Circle()
                        .fill(color)
                        .frame(width: 4, height: 4)
                        .padding(.top, 5)
                    Text(item)
                        .kajiFont(size: 10)
                        .foregroundStyle(KajiTheme.fgDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
