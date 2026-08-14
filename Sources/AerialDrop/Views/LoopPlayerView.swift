import AVFoundation
import SwiftUI

/// A looping AVPlayerLayer-backed player for a local video URL.
struct LoopPlayerView: NSViewRepresentable {
    let url: URL
    let isPlaying: Bool

    func makeNSView(context: Context) -> PlayerNSView {
        PlayerNSView(url: url, isPlaying: isPlaying)
    }

    func updateNSView(_ nsView: PlayerNSView, context: Context) {
        nsView.update(url: url, isPlaying: isPlaying)
    }

    static func dismantleNSView(_ nsView: PlayerNSView, coordinator: Void) {
        nsView.teardown()
    }
}

final class PlayerNSView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    init(url: URL, isPlaying: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspect
        load(url: url, isPlaying: isPlaying)
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

    func update(url: URL, isPlaying: Bool) {
        if currentURL != url {
            load(url: url, isPlaying: isPlaying)
        } else {
            updatePlayback(isPlaying: isPlaying)
        }
    }

    func teardown() {
        looper?.disableLooping()
        player?.pause()
        looper = nil
        player = nil
        playerLayer.player = nil
        currentURL = nil
    }

    private func load(url: URL, isPlaying: Bool) {
        teardown()
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        let queuePlayer = AVQueuePlayer()
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        self.player = queuePlayer
        self.looper = looper
        currentURL = url
        playerLayer.player = queuePlayer
        updatePlayback(isPlaying: isPlaying)
    }

    private func updatePlayback(isPlaying: Bool) {
        if isPlaying {
            player?.play()
        } else {
            player?.pause()
        }
    }
}
