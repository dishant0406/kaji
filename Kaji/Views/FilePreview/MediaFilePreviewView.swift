import AVKit
import SwiftUI

struct MediaFilePreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context _: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        return view
    }

    func updateNSView(_ view: AVPlayerView, context _: Context) {
        if (view.player?.currentItem?.asset as? AVURLAsset)?.url == url { return }
        view.player = AVPlayer(url: url)
    }
}
