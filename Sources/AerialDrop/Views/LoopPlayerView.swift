import AVFoundation
import SwiftUI

/// A looping AVPlayerLayer-backed player for a local video URL.
struct LoopPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PlayerNSView {
        PlayerNSView(url: url)
    }

    func updateNSView(_ nsView: PlayerNSView, context: Context) {
        nsView.update(url: url)
    }

    static func dismantleNSView(_ nsView: PlayerNSView, coordinator: Void) {
        nsView.teardown()
    }
}

final class PlayerNSView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    init(url: URL) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspect
        load(url: url)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    func update(url: URL) {
        guard let item = player?.currentItem,
              (item.asset as? AVURLAsset)?.url == url else {
            load(url: url)
            return
        }
    }

    func teardown() {
        looper?.disableLooping()
        player?.pause()
        looper = nil
        player = nil
        playerLayer.player = nil
    }

    private func load(url: URL) {
        teardown()
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        let queuePlayer = AVQueuePlayer()
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        queuePlayer.play()
        self.player = queuePlayer
        self.looper = looper
        playerLayer.player = queuePlayer
    }
}