import Kaset
import SwiftUI

struct KasetNowPlayingFooterControl: View {
    let controller: KasetEmbeddedController
    @State private var showsQueue = false

    var body: some View {
        let snapshot = controller.nowPlaying
        HStack(spacing: 7) {
            Button {
                NotificationCenter.default.post(name: .toggleKasetMusicPanel, object: nil)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.title)
                        .kajiFont(size: 11, weight: .semibold)
                        .foregroundStyle(KajiTheme.fg)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(snapshot.subtitle)
                        .kajiFont(size: 10)
                        .foregroundStyle(KajiTheme.fgMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(width: 122, alignment: .leading)
            }
            .buttonStyle(.plain)

            IconButton(
                symbol: "backward.fill",
                size: 9,
                accessibilityLabel: "Previous Kaset Track"
            ) {
                controller.previous()
            }

            Slider(
                value: progressBinding(snapshot),
                in: 0 ... max(snapshot.duration, 1)
            )
            .disabled(snapshot.duration <= 0)

            Text(timeText(snapshot.progress))
                .kajiFont(size: 10)
                .foregroundStyle(KajiTheme.fgDim)
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)

            IconButton(
                symbol: snapshot.isPlaying ? "pause.fill" : "play.fill",
                size: 10,
                accessibilityLabel: snapshot.isPlaying ? "Pause Kaset" : "Play Kaset"
            ) {
                controller.playPause()
            }

            IconButton(
                symbol: "forward.fill",
                size: 9,
                accessibilityLabel: "Next Kaset Track"
            ) {
                controller.next()
            }

            IconButton(
                symbol: "list.bullet",
                size: 10,
                accessibilityLabel: "Kaset Queue"
            ) {
                showsQueue.toggle()
            }
            .kajiPopover(isPresented: $showsQueue, preferredEdge: .top) {
                KasetQueueFooterPopover(controller: controller) {
                    showsQueue = false
                }
            }

            IconButton(
                symbol: "xmark",
                size: 9,
                accessibilityLabel: "Quit Kaset Player"
            ) {
                controller.stopPlayback()
                NotificationCenter.default.post(name: .closeKasetMusicPanel, object: nil)
            }
        }
        .frame(height: 30)
    }

    private func progressBinding(_ snapshot: KasetNowPlayingSnapshot) -> Binding<Double> {
        Binding(
            get: { min(max(snapshot.progress, 0), max(snapshot.duration, 0)) },
            set: { controller.seek(to: $0) }
        )
    }

    private func timeText(_ value: TimeInterval) -> String {
        guard value.isFinite, value > 0 else { return "0:00" }
        let seconds = Int(value.rounded())
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

private struct KasetQueueFooterPopover: View {
    let controller: KasetEmbeddedController
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(KajiTheme.border)
            if controller.queueItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(controller.queueItems) { item in
                            Button {
                                controller.playQueueItem(id: item.id)
                                onDismiss()
                            } label: {
                                row(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(width: 360, height: 420)
        .background(KajiTheme.elevatedBackground)
    }

    private var header: some View {
        HStack(spacing: 8) {
            KajiIcon(systemName: "list.bullet", size: 12)
                .foregroundStyle(KajiTheme.fgMuted)
            Text("Kaset Queue")
                .kajiFont(size: 12, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Spacer(minLength: 0)
            IconButton(symbol: "xmark", size: 10, accessibilityLabel: "Close Queue") {
                onDismiss()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            KajiIcon(systemName: "music.note", size: 18)
                .foregroundStyle(KajiTheme.fgDim)
            Text("Queue is empty")
                .kajiFont(size: 12, weight: .medium)
                .foregroundStyle(KajiTheme.fgMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ item: KasetQueueItemSnapshot) -> some View {
        HStack(spacing: 8) {
            KajiIcon(systemName: item.isCurrent ? "speaker.wave.2.fill" : "music.note", size: 11)
                .foregroundStyle(item.isCurrent ? KajiTheme.accent : KajiTheme.fgDim)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(item.title)
                        .kajiFont(size: 12, weight: item.isCurrent ? .semibold : .medium)
                        .foregroundStyle(item.isCurrent ? KajiTheme.accent : KajiTheme.fg)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if item.isSuggested {
                        Text("Suggested")
                            .kajiFont(size: 9, weight: .medium)
                            .foregroundStyle(KajiTheme.fgDim)
                    }
                }
                Text(item.subtitle)
                    .kajiFont(size: 10)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            Text(item.durationText)
                .kajiFont(size: 10)
                .foregroundStyle(KajiTheme.fgDim)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(item.isCurrent ? KajiTheme.accent.opacity(0.08) : .clear)
    }
}
